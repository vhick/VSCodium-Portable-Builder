# VSCodium Portable Builder — ZIP-Only Edition

**One GitHub repository, one manual workflow, one portable ZIP. No PAF installer builder.**

This is the consolidated, cleaned-up copy of the **working VSCodium Portable ZIP builder with the original official VSCodium icon**. It is designed for a separate repository named `VSCodium-Portable-Builder`; you do not need to fork VSCodium. It downloads an official stable Windows ZIP, verifies GitHub's release SHA-256, prepares a community launcher, and publishes a portable ZIP artifact. It does **not** compile VSCodium from source and does **not** build a `.paf.exe`.

## 1. What to delete from your existing GitHub repository

Open your existing GitHub repository and delete these **two old PAF-builder files**:

1. `.github/workflows/build-vscodium-paf.yml`
2. `builder/build_paf.ps1`

To delete a file using GitHub's website: open it, use the **...** menu near the upper-right of the file view, select **Delete file**, and **Commit changes**. The PAF option disappears from the Actions sidebar once the workflow is deleted from the default branch (some old historical runs may still be visible).

**Optional cleanup:** if you published the installer build-tool file in **Releases** as tag `portableapps-installer-tool-3.9.22`, you may delete **that specific release** and, if you choose, its associated tag. It is **not required** for the working ZIP builder. Do **not** delete any VSCodium portable ZIP build artifacts or your application `Data` folder.

**Replace the root `README.md`** with the one inside this kit. The old README on GitHub still discusses PAF packaging and no longer describes the workflow you want.

## 2. The exact files to keep / upload

Extract the ZIP. At the root of the extracted kit you will see:

```text
.github/
  workflows/
    build-vscodium-portable.yml
builder/
  VSCodiumPortable.cs
  build_portable.py
  compile_launcher.ps1
  package_staged.py
tests/
  test_builder.py
README.md
START-HERE.txt
```

These are **all** the files in the cleaned kit. It contains **no** `build-vscodium-paf.yml` and **no** `build_paf.ps1`.

If your existing ZIP builder already works, its **program files do not need changing**. This pack keeps their behavior intact and updates the instructions for the ZIP-only setup. To refresh the repository completely, upload and replace the matching files from the ZIP. Be sure to use the existing `.github/workflows` folder on GitHub rather than trying to upload `.github` directly.

### Browser-only upload steps

1. Open your existing `VSCodium-Portable-Builder` GitHub repository.
2. In `builder`, upload the four files from the ZIP's `builder` folder. Commit the changes.
3. In `tests`, upload `test_builder.py`. Commit the changes.
4. Open `.github` -> `workflows` on GitHub. Upload **only** `build-vscodium-portable.yml` from this kit's `.github/workflows` directory. Commit.
5. At the repository root, upload/replace `README.md` and `START-HERE.txt` and commit.
6. Confirm the two PAF files listed in Section 1 are no longer in the default branch.

If GitHub's browser upload does not let you replace a same-named file, open the existing file, click **Edit**, replace its contents with the file from the ZIP, and commit; alternatively use GitHub Desktop.

## 3. Run the working portable ZIP workflow

1. In your repository, choose **Actions**.
2. Click **Build VSCodium True Portable (Manual)**.
3. Click **Run workflow** (choose `main` as the branch).
4. For your first repeat build, use `release_version = 1.140.06880` and `architecture = x64` for a typical 64-bit Intel/AMD Windows PC. Use `arm64` only on Windows ARM computers.
5. Click **Run workflow** to start a **new run**. (The builder is manual; it does not automatically fetch the latest release.)
6. On a **green successful run**, download the **VSCodium-TruePortable-<version>-<architecture>** artifact from the run's **Artifacts** section.
7. Extract the downloaded artifact ZIP. Inside, extract `VSCodiumPortable-<version>-win-<architecture>-AppDataOther.zip`.
8. Open `VSCodiumPortable` and **always run `VSCodiumPortable.exe` at its root**, not `App/VSCodium/VSCodium.exe`.

If a future stable release changes official ZIP assets or icon files, the workflow may fail; do not disable checksum checks or source validations just to force an output.

## 4. Resulting portable application folder layout

```text
VSCodiumPortable/
  VSCodiumPortable.exe     <- official VSCodium icon; ALWAYS launch this
  App/                     <- REPLACE ON UPDATE
    VSCodium/
      VSCodium.exe
      ... official app files ...
    AppInfo/
      appinfo.ini
      appicon.ico
      appicon_16.png
      appicon_32.png
      appicon_128.png
      Launcher/VSCodiumPortable.ini (optional metadata)
  Data/                    <- KEEP ON UPDATE
    VSCodium/
      user-data/
      extensions/
      tmp/
  Other/                   <- replaceable documentation and build details
```

This uses the original multi-resolution `code.ico` from the selected official VSCodium release to compile the root launcher and create `AppInfo` icons. The launcher sets `VSCODE_PORTABLE` so the editor saves settings/extensions in `Data/VSCodium` without moving folders on startup or shutdown.

## 5. Updating without losing settings

1. Close **all VSCodium windows and related processes**.
2. **Back up the existing `VSCodiumPortable/Data` folder** to a safe location.
3. Run the ZIP workflow with the desired stable release version and download its successful artifact.
4. Extract the **new** portable ZIP into a separate temporary folder.
5. In the **old/current installation**, replace `App/`, `Other/`, and root `VSCodiumPortable.exe` using those from the **new** package.
6. **Do not overwrite, merge, or delete your current `Data` folder**. The newly built ZIP includes only starter, empty user data folders.
7. Launch `VSCodiumPortable.exe`; check your settings, installed extensions, and profiles. Keep the data backup until everything works.

The above instructions refer to moving between editions that both use this App/Data/Other layout. If migrating from a much older ZIP whose data folder was next to `VSCodium.exe`, transfer `data/user-data` and `data/extensions` into `Data/VSCodium` once, after backing them up.

## 6. Portability limits and testing

The source ZIP and checksum are verified before packaging. The portable storage directory is passed to VSCodium using `VSCODE_PORTABLE`, and the custom launcher avoids changing global PATH or registry settings. **Extensions, Git, Python, Node, credential providers, and Windows itself may still create files outside the portable directory**. A successful workflow run proves packaging, not that every plugin is completely isolated. For maximum assurance, test your actual extension set on Windows before/after launch.

The offline test suite checks release rules, ZIP path safety, launcher layout, checksum requirements, official icon handling, and the App-versus-Data separation. The existing workflow has been successfully used by the recipient; this consolidation does not independently rerun that Windows workflow.

### Useful links

- Official VSCodium: https://github.com/VSCodium/vscodium
- Official VS Code portable behavior: https://code.visualstudio.com/docs/setup/portable
- Manually run workflows: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
- Delete a GitHub repository file: https://docs.github.com/en/repositories/working-with-files/managing-files/deleting-files-in-a-repository

Community packaging; not an official VSCodium or PortableApps.com distribution.
