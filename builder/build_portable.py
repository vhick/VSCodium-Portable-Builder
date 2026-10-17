"""Community VSCodium portable ZIP packager.

Uses ONLY official GitHub release ZIP assets. Explicit stable tag + SHA-256
verification. Activates native VSCodium portable mode by placing ``data`` next
to ``VSCodium.exe``; no new executables or registry changes.

Runs using Python 3.13 on a GitHub-hosted Windows runner.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

UPSTREAM = "VSCodium/vscodium"
API_URL = "https://api.github.com/repos/VSCodium/vscodium/releases/tags/"
ASSET_URL_PREFIX = "https://github.com/VSCodium/vscodium/releases/download/"
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SHA256_RE = re.compile(r"^sha256:([a-fA-F0-9]{64})$")
ARCHITECTURES = ("x64", "arm64")


class BuildError(RuntimeError):
    """Reported errors deliberately stop GitHub Actions."""


def expected_asset(version: str, architecture: str) -> str:
    if not VERSION_RE.fullmatch(version):
        raise BuildError("Use an official stable tag, e.g. 1.140.06880 (no v, beta or latest).")
    if architecture not in ARCHITECTURES:
        raise BuildError("Select x64 or arm64 for Windows.")
    return f"VSCodium-win32-{architecture}-{version}.zip"


def choose_asset(release: dict, version: str, architecture: str) -> dict:
    """Validate version, stable status, filename, checksum, size and URL."""
    filename = expected_asset(version, architecture)
    if release.get("tag_name") != version:
        raise BuildError("Release API returned a tag different from the requested version.")
    if release.get("draft") or release.get("prerelease"):
        raise BuildError("Only published stable releases are allowed.")
    assets = [a for a in release.get("assets", []) if a.get("name") == filename]
    if len(assets) != 1:
        raise BuildError(f"Official release does not provide {filename}.")
    asset = assets[0]
    if asset.get("state") != "uploaded":
        raise BuildError("Selected upstream asset is not fully uploaded.")
    if not isinstance(asset.get("size"), int) or asset["size"] < 1_000_000:
        raise BuildError("Suspicious or unavailable Windows ZIP asset size.")
    if not isinstance(asset.get("digest"), str) or not SHA256_RE.fullmatch(asset["digest"]):
        raise BuildError("The official asset has no usable SHA-256 digest. Refusing unverified download.")
    exact_url = ASSET_URL_PREFIX + version + "/" + filename
    if asset.get("browser_download_url") != exact_url:
        raise BuildError("Official asset download URL differs from expected GitHub release URL.")
    return asset


def _github_api_json(url: str, token: str | None):
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "community-vscodium-portable-builder",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            if response.status != 200:
                raise BuildError(f"GitHub Releases API replied with HTTP {response.status}.")
            return json.load(response)
    except (urllib.error.HTTPError, urllib.error.URLError) as exc:
        raise BuildError(f"Could not read official GitHub release information: {exc}") from exc


def fetch_release(version: str, token: str | None = None) -> dict:
    expected_asset(version, "x64")
    release = _github_api_json(API_URL + version, token)
    release_id = release.get("id")
    if not isinstance(release_id, int) or release_id < 1:
        raise BuildError("GitHub release metadata is missing its release ID.")
    # VSCodium releases can have 180+ assets. The release detail response may
    # not include all of them. Page through ALL assets rather than assuming the
    # desired Windows ZIP is in the first page of a nested assets list.
    all_assets = []
    for page in range(1, 21):
        url = (f"https://api.github.com/repos/VSCodium/vscodium/releases/"
               f"{release_id}/assets?per_page=100&page={page}")
        batch = _github_api_json(url, token)
        if not isinstance(batch, list):
            raise BuildError("Unexpected GitHub release assets response.")
        all_assets.extend(batch)
        if len(batch) < 100:
            break
    else:
        raise BuildError("More release assets than supported by the safety limit.")
    release["assets"] = all_assets
    print(f"Found {len(all_assets)} files in official release {version}.")
    return release


def download_verified(asset: dict, destination: Path) -> str:
    url = asset["browser_download_url"]
    expected_sha = SHA256_RE.fullmatch(asset["digest"]).group(1).lower()
    # GitHub's release redirect serves large files; use streams, not RAM loading.
    request = urllib.request.Request(
        url, headers={"User-Agent": "community-vscodium-portable-builder"}
    )
    digest = hashlib.sha256()
    size = 0
    try:
        with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as outfile:
            if response.status != 200:
                raise BuildError(f"GitHub returned HTTP {response.status} for release download.")
            while True:
                block = response.read(2 * 1024 * 1024)
                if not block:
                    break
                outfile.write(block)
                digest.update(block)
                size += len(block)
    except (urllib.error.URLError, OSError) as exc:
        raise BuildError(f"Official VSCodium ZIP download failed: {exc}") from exc
    actual_sha = digest.hexdigest()
    if size != asset["size"]:
        raise BuildError(f"Download size mismatch: expected {asset['size']}, got {size} bytes.")
    if actual_sha != expected_sha:
        raise BuildError("SHA-256 verification failed. The downloaded file will NOT be packaged.")
    print(f"Verified upstream ZIP: {asset['name']} ({size:,} bytes)")
    print(f"GitHub release SHA-256: {actual_sha}")
    return actual_sha


def _validate_members(zf: zipfile.ZipFile) -> None:
    filenames = set()
    for entry in zf.infolist():
        p = entry.filename.replace("\\", "/")
        parts = PurePosixPath(p).parts
        if (not p or p.startswith("/") or p.startswith("//") or ":" in p or
                any(x in (".", "..") for x in parts) or "\x00" in p):
            raise BuildError(f"Unsafe path in upstream ZIP: {entry.filename!r}")
        # Don't trust symlinks in an archive to change the extraction root.
        mode = entry.external_attr >> 16
        if stat.S_IFMT(mode) == stat.S_IFLNK:
            raise BuildError(f"Unexpected symlink in Windows ZIP: {entry.filename!r}")
        lowered = p.casefold()
        if lowered in filenames:
            raise BuildError("Duplicate archive path detected: " + p)
        filenames.add(lowered)


def unpack_official_zip(src: Path, target: Path) -> None:
    try:
        with zipfile.ZipFile(src) as zf:
            _validate_members(zf)
            zf.extractall(target)
    except zipfile.BadZipFile as exc:
        raise BuildError("Official upstream download is not a valid ZIP.") from exc
    exe = target / "VSCodium.exe"
    if not exe.is_file():
        # Some upstream ZIPs may contain an enclosing folder. Flatten ONE level only.
        candidates = [p for p in target.iterdir() if p.is_dir() and (p / "VSCodium.exe").is_file()]
        if len(candidates) != 1 or len(list(target.iterdir())) != 1:
            raise BuildError("Unexpected upstream ZIP structure: VSCodium.exe not found at the expected root.")
        for member in candidates[0].iterdir():
            shutil.move(str(member), str(target / member.name))
        candidates[0].rmdir()
    if not exe.is_file() or not (target / "resources").is_dir():
        raise BuildError("Upstream ZIP does not have the expected VSCodium Windows layout.")
    data_dir = target / "data"
    if data_dir.exists() and any(data_dir.iterdir()):
        raise BuildError("Upstream archive already contains nonempty data; refusing to overwrite.")


def enable_portable_mode(target: Path, version: str, architecture: str, source_sha: str) -> None:
    data_dir = target / "data"
    for name in ("user-data", "extensions", "tmp"):
        folder = data_dir / name
        folder.mkdir(parents=True, exist_ok=True)
        # A real file ensures GitHub ZIP downloads preserve the initially empty folders.
        (folder / ".keep").write_text("Created by portable builder; safe to leave in place.\n", encoding="utf-8")
    (target / "PORTABLE-README.txt").write_text(
        "VSCODIUM PORTABLE (COMMUNITY PACKAGE)\n"
        "\nOpen VSCodium.exe from THIS folder. Native portable mode is enabled by data/.\n"
        "Settings, extensions and editor state are saved in data/.\n"
        "For upgrades, back up data/, then move the old data/ directory into a\n"
        "freshly extracted new version, replacing the new EMPTY data/ directory.\n"
        "Never mix application files from different versions.\n"
        "Some extensions and external tools may write to the Windows user profile.\n"
        "This package is not endorsed by the VSCodium developers.\n"
        f"\nVersion: {version}\nArchitecture: Windows {architecture}\n"
        f"Verified source ZIP SHA-256: {source_sha}\n"
        "Official releases: https://github.com/VSCodium/vscodium/releases\n",
        encoding="utf-8",
    )


def create_zip(portable_root: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6,
                         allowZip64=True) as zf:
        for p in sorted(portable_root.rglob("*")):
            rel = str(p.relative_to(portable_root.parent)).replace("\\", "/")
            if p.is_dir():
                zf.writestr(rel + "/", "")
            else:
                zf.write(p, rel)
    with zipfile.ZipFile(output) as zf:
        archive_names = set(zf.namelist())
        required = {
            "VSCodiumPortable/VSCodium.exe",
            "VSCodiumPortable/data/",
            "VSCodiumPortable/data/user-data/",
            "VSCodiumPortable/data/extensions/",
            "VSCodiumPortable/data/tmp/",
            "VSCodiumPortable/PORTABLE-README.txt",
        }
        missing = required - archive_names
        if missing:
            raise BuildError(f"Portable ZIP verification failed; missing: {sorted(missing)}")
        bad = zf.testzip()
        if bad:
            raise BuildError(f"CRC check failed for packaged file: {bad}")
    print(f"Ready: {output} ({output.stat().st_size:,} bytes)")


def build(version: str, architecture: str, output_dir: Path) -> Path:
    filename = expected_asset(version, architecture)
    print(f"Official upstream: {UPSTREAM}")
    print(f"Selected stable release: {version}; Windows architecture: {architecture}")
    release = fetch_release(version, token=os.getenv("GITHUB_API_TOKEN"))
    asset = choose_asset(release, version, architecture)
    with tempfile.TemporaryDirectory(prefix="vscodium-builder-") as temp_path:
        temp = Path(temp_path)
        incoming = temp / filename
        source_sha = download_verified(asset, incoming)
        root = temp / "VSCodiumPortable"
        root.mkdir()
        unpack_official_zip(incoming, root)
        enable_portable_mode(root, version, architecture, source_sha)
        output = output_dir / f"VSCodiumPortable-{version}-win-{architecture}.zip"
        create_zip(root, output)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description="Package official stable VSCodium for Windows portable mode")
    parser.add_argument("--version", required=True, help="Upstream version tag, e.g. 1.140.06880")
    parser.add_argument("--architecture", choices=ARCHITECTURES, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("dist"))
    args = parser.parse_args()
    try:
        build(args.version, args.architecture, args.output_dir)
    except BuildError as exc:
        parser.exit(1, f"BUILD STOPPED: {exc}\n")


if __name__ == "__main__":
    main()
