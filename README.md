# Additional workflow: ready-made VSCodium PortableApps `.paf.exe`

**This is an add-on for your existing `VSCodium-Portable-Builder`. No new repository is needed.**

After you add two files, your existing ZIP workflow is unaffected:

| Existing | New |
| --- | --- |
| `Build VSCodium True Portable (Manual)` | `Build VSCodium PortableApps PAF (Manual)` |
| `.zip` artifact | `.paf.exe` inside an Actions artifact ZIP |

## Install in GitHub's website (no coding)

1. Extract this build-kit add-on ZIP.
2. Open your current **VSCodium-Portable-Builder** repository.
3. Open the **builder** folder. Click **Add file → Upload files** and upload the extracted `builder/build_paf.ps1` file (not the folder). Commit the change.
4. Open **.github → workflows** in the same repository. Click **Add file → Upload files** and upload the extracted `.github/workflows/build-vscodium-paf.yml` file (not `.github` itself). Commit.
5. Under **Actions**, select **Build VSCodium PortableApps PAF (Manual)**.
6. Click **Run workflow**, choose the release and architecture, then click **Run workflow** again.
7. After a successful green checkmark, download the `VSCodium-PAF-…` artifact. GitHub first wraps the `.paf.exe` inside an artifact ZIP; extract that ZIP to access the `.paf.exe` installer.

## Result

`VSCodiumPortable_<version>_<architecture>_Community.paf.exe`

The `.paf.exe` installs this familiar structure, retaining the original VSCodium multi-resolution icon:

```text
VSCodiumPortable/
  App/
    VSCodium/
    AppInfo/
      appinfo.ini
      installer.ini             <-- keeps existing Data on upgrades
      appicon.ico
  Data/
    VSCodium/
      user-data/
      extensions/
      tmp/
  Other/
  VSCodiumPortable.exe         <-- always open this launcher
```

The launcher is the same tested **community** launcher as your original ZIP package. This is not an official VSCodium or PortableApps.com published app.

## Updates and data safety

- Close VSCodium completely and back up your existing `VSCodiumPortable/Data` folder before any upgrade.
- Run the **PAF workflow** with a newer official stable version. It uses the same `builder/build_portable.py` release-integrity check, `compile_launcher.ps1` icon and launcher build, and `package_staged.py` package check as the existing ZIP workflow.
- Run the new `.paf.exe` and **install into the same parent PortableApps folder** where your existing `VSCodiumPortable` folder lives.
- The generated package includes:

```ini
[MainDirectories]
RemoveAppDirectory=true
RemoveDataDirectory=false
RemoveOtherDirectory=true
```

These are the official PortableApps.com Installer directives for replacing the program while **not deleting the existing Data directory**. There is never a guarantee against corrupted files, so keep a backup until you verify settings/extensions.

- Different architecture builds (x64 / ARM64) must not be mixed casually with a running installation.
- Temporary host files may still be created by Windows or extensions; packaging alone does not demonstrate complete portability.

## Integrity and reproducibility

- VSCodium downloaded only from official GitHub release assets, checked against the publisher's GitHub SHA-256 digest.
- Official PortableApps.com Installer **3.9.22** downloaded from the SourceForge publisher URL and checked against SHA-256 **`689456f1fb1320c45e82a077afe6b87fb388fd3f75c41d9ee9ce8d45f3966b67`** published on its SourceForge download page.
- The installer packager is installed **only on the temporary GitHub Windows runner**, not on your computer.
- The packager receives the fully staged `stage/VSCodiumPortable` folder from the existing code.
- No permanent Windows PATH or registry edits are used by our launcher.

**Important limitation:** The scripts pass syntax/static checks here; a complete GitHub Windows run and the generated `.paf.exe` upgrade behavior have **not yet been tested**. If the official installer fails to run silently or SourceForge blocks a download, the workflow will fail rather than upload an incomplete `.paf.exe`. The bootstrap process uses PortableApps.com Installer `/S` and `/DESTINATION`; this is the part that requires Windows validation.

## References

- [PortableApps.com Installer](https://portableapps.com/apps/development/portableapps.com_installer)
- [PortableApps.com installer.ini data preservation](https://portableapps.com/manuals/PortableApps.comLauncher/ref/paf/installer.html)
- [Official stable installer download / SHA256](https://sourceforge.net/projects/portableapps/files/PortableApps.com%20Installer/PortableApps.comInstaller_3.9.22.paf.exe/download)
- [VSCodium official repository](https://github.com/VSCodium/vscodium)
