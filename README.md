# VSCodium Portable Builder — Revised App / Data / Other Edition

**This is the corrected version of the previous builder kit.** It produces the **same top-level layout as YTSagePortable**, with a dedicated `VSCodiumPortable.exe` launcher, program files under `App`, and persistent settings/extensions inside `Data`.

**Status:** 12 offline packaging/security/layout tests passed. This is a prepared GitHub Actions builder kit — **not** the finished Windows app. The GitHub Actions Windows compilation and VSCodium runtime portability tests remain unverified.

## The resulting portable application

```text
VSCodiumPortable/
  VSCodiumPortable.exe           <-- ALWAYS open this launcher
  App/                            <-- REPLACE during upgrades
    VSCodium/
      VSCodium.exe                <-- internal program; do not launch directly
      bin/
      resources/
      ... other upstream files ...
    AppInfo/
      appinfo.ini
      appicon.ico
      appicon_16.png
      appicon_32.png
      appicon_128.png
      Launcher/VSCodiumPortable.ini
  Data/                           <-- KEEP your existing Data during upgrades
    VSCodium/
      user-data/                  <-- settings, profiles, editor state
      extensions/                 <-- extensions
      tmp/                        <-- temp files
  Other/
    README-PORTABLE.txt
    Source/Build-Information.txt
```

### Why the custom launcher is essential

The official Windows ZIP normally enables portable mode by placing `data` next to `VSCodium.exe`. That is valid native portability, but it puts persistent user data **inside our `App/` folder**, creating a risk during upgrades that replace `App`.

The underlying VS Code runtime also supports `VSCODE_PORTABLE` to choose a portable data directory. Our small Windows launcher creates `Data/VSCodium` and starts the **official, unmodified VSCodium.exe** with `VSCODE_PORTABLE` pointing to that directory. The runtime uses it for editor user-data, extensions and temp files. We do **not** move any directories before/after runs, create Windows junctions, or edit system-level environment variables. The launcher changes environment variables for the VSCodium process only.

Official source: https://github.com/microsoft/vscode/blob/main/src/bootstrap-node.ts (`configurePortable`). VSCodium confirms that the Windows ZIP follows VS Code's portable-mode behavior: https://github.com/VSCodium/vscodium/blob/master/docs/usage.md

## Update your EXISTING GitHub builder repository

You do **not** need another builder repository, a fork, GitHub Desktop, or a command line.

1. Download the **revised** builder kit ZIP and **Extract All** on Windows.
2. Go to your existing **VSCodium-Portable-Builder** repository on GitHub. Open the **`builder`** folder. Click **Add file → Upload files**, then add/replace these four files from the extracted `builder` folder:
   - `build_portable.py`
   - `VSCodiumPortable.cs`
   - `compile_launcher.ps1`
   - `package_staged.py`
3. Click **Commit changes**. This replaces the old Python builder and adds the new launcher source and packaging files.
4. Go to the **`tests`** folder. Upload/replace the new `test_builder.py`. Commit.
5. Go to the existing **`.github/workflows`** folder in your GitHub repository. Upload/replace **only** `build-vscodium-portable.yml` from the new kit's `.github/workflows` folder, then commit. **Do not upload `.github` itself**; use the folder already present on GitHub.
6. Optional: replace the repository's `README.md` and `START-HERE.txt` with the new versions so your future instructions remain accurate.
7. Verify the repository has the four builder files, revised test, and revised workflow. Then open **Actions → Build VSCodium True Portable (Manual)** and run the workflow.

If your GitHub upload page will not accept a file with the same name, click the existing file in GitHub and use the pencil icon to **Edit file**, replacing the contents with the text from the revised file. Commit the change. GitHub Desktop is another option, but isn't required.

### If you have not yet created a GitHub repository

1. Go to https://github.com/new and create an empty public repository `VSCodium-Portable-Builder`. Do not add a README, .gitignore or license at creation.
2. Extract the kit ZIP. Upload `builder/`, `tests/`, `README.md`, and `START-HERE.txt` into the empty repo. Commit.
3. For the hidden `.github` folder, choose **Add file → Create new file** and type `.github/workflows/README.md`; type `Workflow folder` and commit. Then open `.github/workflows` in GitHub and upload **only** `build-vscodium-portable.yml`. Commit.
4. Go to **Actions**, enable workflows if prompted, and run **Build VSCodium True Portable (Manual)**.

## Running and downloading the build

1. On GitHub open **Actions → Build VSCodium True Portable (Manual) → Run workflow**.
2. For the first build use `release_version = 1.140.06880`, `architecture = x64` (or `arm64` if your computer runs Windows on ARM).
3. Click **Run workflow** again to confirm. This workflow is **manual-only**, not automatic.
4. Open the workflow run. A green checkmark means that its package and structural checks completed. Under **Artifacts**, download `VSCodium-TruePortable-1.140.06880-x64` (or your chosen version/architecture).
5. Extract the downloaded GitHub artifact ZIP. Extract the `VSCodiumPortable-1.140.06880-win-x64-AppDataOther.zip` inside it.
6. Open `VSCodiumPortable/` and run **`VSCodiumPortable.exe`**. Don't run `App/VSCodium/VSCodium.exe` by itself; bypassing the launcher may write to ordinary Windows profile directories.

If the run is red, open the failed step and copy its error log. Source asset changes, GitHub availability, image extraction and Windows compiler issues can cause failures that offline unit tests cannot detect.

## Safe updates — preserve your Data directory

**When the new package has the same App/Data/Other structure:**

1. Close VSCodium completely and back up the *old* `VSCodiumPortable/Data` folder.
2. Download and extract the new portable package into a separate temporary folder.
3. In your existing installation, **replace the entire `App` folder**, then copy `Other` and `VSCodiumPortable.exe` from the new package.
4. **Do not replace, merge or delete your old `Data` folder.** The new ZIP contains empty starter data directories, not your personal settings.
5. Launch the updated `VSCodiumPortable.exe`. Verify your extensions, settings and profiles.

This procedure is the same as your YTSage Portable updating workflow.

## Migrate existing settings from the PREVIOUS VSCodium builder ZIP

If you **already ran the original VSCodium builder kit from our last reply**, its output uses a different layout:

```text
OLD: VSCodiumPortable/VSCodium.exe
OLD: VSCodiumPortable/data/user-data
OLD: VSCodiumPortable/data/extensions
OLD: VSCodiumPortable/data/tmp
```

To migrate **once** to the corrected build:

1. Completely close the old VSCodium and back up its entire **old `data` folder**.
2. Extract the new corrected ZIP into an **entirely new folder**. Do not merge two different program layouts.
3. From the **old** `VSCodiumPortable/data/` folder, copy `user-data/`, `extensions/`, and (if desired) `tmp/` into the **new** `VSCodiumPortable/Data/VSCodium/` folder. The new folders are empty except for `.keep` marker files.
4. Start the **new** `VSCodiumPortable.exe`. Confirm your settings and extensions are present.
5. Keep the old copy as a backup until everything works. After that, future updates only replace `App`, `Other` and the root launcher.

## What is verified, and what isn't

This kit includes offline tests that verify stable-release naming, upstream asset checksums, ZIP path safety, supported Windows architectures, required package contents, and that no persistent data directory is packaged under `App/VSCodium`. The build checks the published upstream GitHub release metadata and SHA-256 digest at runtime before downloading and packaging. The launcher is compiled using the Windows .NET Framework C# compiler already available on the GitHub-hosted Windows machine.

**What is not yet proven:** successful execution of the full workflow on GitHub; the custom launcher actually running a VSCodium Windows session; no AppData or registry traces from third-party extensions. Portable Windows applications may still leave system-level execution traces, and tools run inside the editor (Git, Python, language servers, terminals, browser auth) may have their own host files. We do not claim otherwise without real Windows tests.

## Included files

```text
.github/workflows/build-vscodium-portable.yml
builder/build_portable.py
builder/VSCodiumPortable.cs
builder/compile_launcher.ps1
builder/package_staged.py
tests/test_builder.py
README.md
START-HERE.txt
```

This builder uses the **official VSCodium ZIP** — it does not compile VSCodium's upstream source and does not require a fork. It bundles a *community launcher* and includes PortableApps-compatible layout/metadata; **it does not automatically generate a `.paf.exe` installer**, and is not an officially approved PortableApps.com release.

### Sources

- VSCodium: https://github.com/VSCodium/vscodium
- VSCodium portable guidance: https://github.com/VSCodium/vscodium/blob/master/docs/usage.md
- VS Code runtime portable environment behavior: https://github.com/microsoft/vscode/blob/main/src/bootstrap-node.ts
- PortableApps standard folder layout: https://portableapps.com/manuals/PortableApps.comLauncher/ref/paf/layout.html
- GitHub manual workflow runs: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow

VSCodium's source, binaries and trademarks remain those of their respective authors. This packaging is a third-party community build and is not endorsed by them.
