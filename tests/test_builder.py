"""Offline-only safety and layout tests. No downloads or GitHub credentials required."""
from __future__ import annotations

import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "builder"))
from build_portable import (
    BuildError, expected_asset, choose_asset, _validate_members,
    unpack_official_zip, enable_portable_mode, create_zip, fetch_release
)

VERSION = "1.140.06880"
NAME = f"VSCodium-win32-x64-{VERSION}.zip"
TEST_SHA = "0" * 64


def fixture_release():
    return {
        "tag_name": VERSION,
        "draft": False,
        "prerelease": False,
        "assets": [{
            "name": NAME,
            "state": "uploaded",
            "size": 200_000_000,
            "digest": "sha256:" + TEST_SHA,
            "browser_download_url": "https://github.com/VSCodium/vscodium/releases/download/"
                                    + VERSION + "/" + NAME,
        }],
    }


class BuilderTests(unittest.TestCase):
    def test_paginated_release_assets(self):
        release = fixture_release()
        release["id"] = 12345
        release["assets"] = []  # truncated release metadata
        first_page = [{"name": f"unrelated-{n}"} for n in range(100)]
        second_page = fixture_release()["assets"]
        with patch("build_portable._github_api_json", side_effect=[release, first_page, second_page]) as mocked:
            full_release = fetch_release(VERSION)
        self.assertEqual(mocked.call_count, 3)
        self.assertEqual(len(full_release["assets"]), 101)
        self.assertEqual(choose_asset(full_release, VERSION, "x64")["name"], NAME)

    def test_stable_release_asset_selection(self):
        a = choose_asset(fixture_release(), VERSION, "x64")
        self.assertEqual(a["name"], NAME)
        self.assertEqual(expected_asset(VERSION, "arm64"),
                         f"VSCodium-win32-arm64-{VERSION}.zip")

    def test_reject_beta_latest_and_version_injection(self):
        for version in ("latest", "1.140.0-beta.1", "1.140.0/../../bad", "v1.140.06880"):
            with self.subTest(version=version), self.assertRaises(BuildError):
                expected_asset(version, "x64")

    def test_reject_prerelease_and_draft(self):
        for field in ("prerelease", "draft"):
            release = fixture_release()
            release[field] = True
            with self.assertRaises(BuildError):
                choose_asset(release, VERSION, "x64")

    def test_reject_missing_or_bad_digest(self):
        for digest in ("", None, "sha256:1234", "md5:" + TEST_SHA):
            release = fixture_release()
            release["assets"][0]["digest"] = digest
            with self.assertRaises(BuildError):
                choose_asset(release, VERSION, "x64")

    def test_reject_wrong_download_source(self):
        release = fixture_release()
        release["assets"][0]["browser_download_url"] = "https://example.org/fake.zip"
        with self.assertRaises(BuildError):
            choose_asset(release, VERSION, "x64")

    def test_reject_zip_traversal_and_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            zip_path = Path(temp) / "bad.zip"
            with zipfile.ZipFile(zip_path, "w") as zf:
                zf.writestr("../escape.txt", "bad")
            with zipfile.ZipFile(zip_path) as zf, self.assertRaises(BuildError):
                _validate_members(zf)

    def test_reject_preexisting_data(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "input.zip"
            out = Path(temp) / "VSCodiumPortable"
            with zipfile.ZipFile(path, "w") as zf:
                zf.writestr("VSCodium.exe", "mock exe")
                zf.writestr("resources/a.txt", "a")
                zf.writestr("data/user-data/existing-user.json", "secret")
            out.mkdir()
            with self.assertRaises(BuildError):
                unpack_official_zip(path, out)

    def test_build_portable_zip_preserves_structure(self):
        with tempfile.TemporaryDirectory() as temp:
            tmp = Path(temp)
            src = tmp / "upstream.zip"
            with zipfile.ZipFile(src, "w") as zf:
                zf.writestr("VSCodium.exe", "mock exe")
                zf.writestr("resources/app/product.json", "{}")
                zf.writestr("bin/codium.cmd", "@echo off")
            root = tmp / "VSCodiumPortable"
            root.mkdir()
            unpack_official_zip(src, root)
            enable_portable_mode(root, VERSION, "x64", "a" * 64)
            result = tmp / "portable.zip"
            create_zip(root, result)
            with zipfile.ZipFile(result) as zf:
                self.assertIn("VSCodiumPortable/VSCodium.exe", zf.namelist())
                for suffix in ("data/", "data/user-data/", "data/extensions/", "data/tmp/"):
                    self.assertIn("VSCodiumPortable/" + suffix, zf.namelist())
                info = zf.read("VSCodiumPortable/PORTABLE-README.txt").decode("utf-8")
                self.assertIn("1.140.06880", info)
                self.assertIn("back up data/", info)
                self.assertNotIn("App\\VSCodium", info)


if __name__ == "__main__":
    unittest.main()
