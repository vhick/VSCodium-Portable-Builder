# VSCodium True Portable — GitHub Actions Builder

**A beginner-friendly, manual-only, standalone GitHub Actions builder for the official Windows ZIP edition of VSCodium.**

- No fork required. You only create a new builder repository of your own.
- No application compilation, source patches, registry modifications, or custom launcher.
- The official VSCodium ZIP is checked using the **SHA-256 digest reported by GitHub's release API** before being repackaged.
- Native portable mode: `data/` is placed **right beside `VSCodium.exe`**, and includes `user-data/`, `extensions/` and `tmp/`.
- Builds are **manual only**. You choose the stable version and Windows architecture (x64 or ARM64).
- Output: portable ZIP downloaded from **Actions > Artifacts** (default retention: 7 days).

**Status:** The builder's offline tests pass. The actual GitHub Actions run, official download, and Windows portability behavior have **not yet been tested**. Running this workflow in GitHub completes that step.

## Part A — Set up the builder (do this only once)

### Step 1: Create a separate repository

1. Sign in to your GitHub account and open https://github.com/new
2. For **Repository name**, enter **VSCodium-Portable-Builder**.
3. Choose **Public** (simplifies setup; never upload passwords or personal data).
4. Select **no README, no .gitignore, no license** so the new repository is empty.
5. Click **Create repository**. **Do not fork VSCodium.**

### Step 2: Extract THIS builder kit ZIP

Right-click the kit ZIP on your computer and select **Extract All**. Open the extracted folder. It contains:

```text
.github/                   <- hidden folder; do not try to upload the folder itself
  workflows/
    build-vscodium-portable.yml
builder/
  build_portable.py
tests/
  test_builder.py
README.md
START-HERE.txt
```

### Step 3: Upload the non-hidden contents

1. On your **VSCodium-Portable-Builder** GitHub page, click **uploading an existing file**. If you already have some files, use **Add file > Upload files**.
2. From Windows File Explorer, drag in **`builder`**, **`tests`**, **`README.md`**, and **`START-HERE.txt`**. **Do not drag the downloaded ZIP**.
3. Check that GitHub lists files under `builder/` and `tests/`, then **Commit changes**.
4. **Do not upload `.github` here**. Use the next step instead.

### Step 4: Create the special `.github/workflows` folder without uploading a dot-folder

1. In your builder repo, click **Add file > Create new file**.
2. For the new filename, type **`.github/workflows/README.md`**. GitHub creates both directories automatically after the slashes.
3. In the body, type: `Workflow folder`.
4. Click **Commit changes**. This placeholder is harmless.
5. Return to the repo and navigate into **`.github` > `workflows`**.
6. Click **Add file > Upload files**.
7. On your computer, open the extracted kit's `.github/workflows/` folder, and **upload only** `build-vscodium-portable.yml`.
8. Click **Commit changes**.

Your GitHub repository should now contain:

```text
VSCodium-Portable-Builder/
  .github/
    workflows/
      README.md
      build-vscodium-portable.yml
  builder/
    build_portable.py
  tests/
    test_builder.py
  README.md
  START-HERE.txt
```

## Part B — Build VSCodium Portable

1. Open your **VSCodium-Portable-Builder** repository on GitHub.
2. Click **Actions**. If prompted, enable Actions in **your own** repository.
3. Choose **Build VSCodium True Portable (Manual)** on the left.
4. Click **Run workflow**.
5. Set:
   - **Branch:** `main` (or your repository's default branch)
   - **release_version:** `1.140.06880` (initial verified release-name format; replace with a newer official **stable** tag when available)
   - **architecture:** `x64` for most Windows desktops/laptops; `arm64` only for Windows-on-ARM computers.
6. Click the green **Run workflow** button.
7. A successful run shows a **green check**. Open that run, scroll to **Artifacts**, and download **VSCodium-TruePortable-1.140.06880-x64** (or your selected values).
8. Extract the downloaded GitHub artifact ZIP. **Inside it is** `VSCodiumPortable-1.140.06880-win-x64.zip`.
9. Extract that inner ZIP. Enter the **VSCodiumPortable** folder and double-click **`VSCodium.exe`**. Do not move it away from the adjacent **`data`** folder.

If the run fails (red X), expand the failed step to read the error. A successful offline test does not guarantee the actual download/extraction succeeds; keep the error log for troubleshooting.

### What the finished app looks like

```text
VSCodiumPortable/
  VSCodium.exe      <-- launch this
  bin/
  resources/
  ... other official program files ...
  data/             <-- KEEP THIS during updates
    user-data/      <-- settings, profiles, state
    extensions/     <-- extensions
    tmp/            <-- portable temporary directory
  PORTABLE-README.txt
```

**Important:** For this editor, **do not** move application files under a separate `App/` folder unless `data/` also stays beside `VSCodium.exe`. The built-in portable mode requires the exact layout shown above.

## Part C — Update safely (preserve ALL your current data)

When an official new stable VSCodium release is available:

1. Run the same GitHub Action again and enter **the exact new stable version** under `release_version`. Running without changing it rebuilds the old version.
2. Download the new successful **Artifacts** ZIP. Extract both ZIP layers into a **NEW folder**. **Do not overwrite the old installation yet.**
3. Close all existing VSCodium windows. Back up your old `VSCodiumPortable/data` folder to a safe location.
4. Inside the **new** extracted `VSCodiumPortable`, **delete ONLY its new/empty `data` folder**. (This folder contains just the initial empty structure and `.keep` markers.)
5. **Copy your old `data` folder** into the new `VSCodiumPortable` folder, directly beside the new `VSCodium.exe`.
6. Start the **new** `VSCodium.exe`. Confirm your extensions, themes and settings remain.
7. Once everything works, keep or archive your previous installation as a backup.

**Never delete your old `data` folder before making a backup, and never merge program files from two versions.** If you already have an existing VSCodium portable ZIP installation, you can move its `data/` folder using these steps.

## What this builder verifies

- The selected release tag is exactly the stable version requested (not beta/draft).
- The correct official Windows ZIP asset exists for your chosen x64/arm64 CPU.
- The asset's download URL is an exact official GitHub release URL.
- GitHub's uploaded asset SHA-256 checksum exists and matches downloaded bytes.
- The ZIP contains expected Windows VSCodium program files; archive paths are checked.
- Portable mode's `data/`, `user-data/`, `extensions/`, and `tmp/` exist.
- The downloadable ZIP can be read without CRC errors.

**No `.paf.exe` is produced.** This is a native self-contained Windows ZIP. Creating a PortableApps.com Format installer is a separate packaging project; making one by renaming `.zip` is invalid.

## True portability limitations

VSCodium's native portable mode redirects its own preferences, profiles, sessions, extensions and temporary folder as documented. It does **not** guarantee that every third-party extension, shell, Git, SSH client, compiler, language server or Windows credential service avoids writing elsewhere on the host. The app may also leave Windows-managed execution traces. **Test your installed extensions and external tools** if strict no-host-remnants portability is essential.

This project does not activate Windows Explorer context menus or install shell integrations. The Windows ZIP version also does not automatically update itself; use the manual workflow again for future versions.

## Authoritative references

- Official VSCodium repository and releases: https://github.com/VSCodium/vscodium/releases
- VSCodium portable-mode guidance: https://github.com/VSCodium/vscodium/blob/master/docs/index.md#how-do-i-run-vscodium-in-portable-mode
- VS Code portable-mode technical details: https://code.visualstudio.com/docs/setup/portable
- GitHub Actions manual run documentation: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
- GitHub release API and SHA-256 asset digests: https://docs.github.com/en/rest/releases/assets

Community-produced packaging only; not affiliated with VSCodium, Microsoft or PortableApps.com. VSCodium's original license and third-party notices remain embedded in the official ZIP.
