# This script is ADDITIVE: it does not alter the existing portable ZIP builder.
# It downloads an unchanged official PortableApps.com Installer from a GH Release
# in the user's builder repository, verifies the PUBLISHER'S pinned SHA-256,
# unpacks the builder, then compiles .paf.exe from App/Data/Other.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][ValidateSet('x64', 'arm64')][string]$Architecture
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Specify an official stable version number.' }

$repositoryRoot = (Get-Location).Path
$appRoot = Join-Path $repositoryRoot 'stage\VSCodiumPortable'
$infoRoot = Join-Path $appRoot 'App\AppInfo'
$source = Join-Path $appRoot 'App\VSCodium\VSCodium.exe'
$launcher = Join-Path $appRoot 'VSCodiumPortable.exe'
$dataDir = Join-Path $appRoot 'Data\VSCodium'
$outputRoot = Join-Path $repositoryRoot 'dist'
if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw 'The staged official VSCodium.exe is missing.' }
if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'VSCodiumPortable.exe launcher is missing.' }
foreach ($subdir in @('user-data', 'extensions', 'tmp')) {
    if (!(Test-Path -LiteralPath (Join-Path $dataDir $subdir) -PathType Container)) {
        throw "Persistent Data folder missing: $subdir"
    }
}
if (Test-Path -LiteralPath (Join-Path $appRoot 'App\VSCodium\data')) {
    throw 'Unsafe package: native data directory found inside App.'
}
$metadataFile = Join-Path $infoRoot 'appinfo.ini'
if (!(Test-Path -LiteralPath $metadataFile)) { throw 'PortableApps appinfo.ini is missing.' }
$metadata = Get-Content -LiteralPath $metadataFile -Raw
if ($metadata -notmatch [regex]::Escape("DisplayVersion=$Version")) { throw 'Package release version is inconsistent.' }
if ($metadata -notmatch 'Start=VSCodiumPortable\.exe') { throw 'PortableApps launcher declaration is missing.' }
foreach ($icon in @('appicon.ico', 'appicon_16.png', 'appicon_32.png')) {
    if (!(Test-Path -LiteralPath (Join-Path $infoRoot $icon))) { throw "Missing official icon file: $icon" }
}

# Explicitly preserve existing user data when the installer upgrades a copy.
# This is the documented PortableApps.com format setting.
$installerIni = @'
[MainDirectories]
RemoveAppDirectory=true
RemoveOtherDirectory=true
RemoveDataDirectory=false
'@
Set-Content -LiteralPath (Join-Path $infoRoot 'installer.ini') -Value $installerIni -Encoding ascii

# This runner cannot reliably fetch PortableApps.com from SourceForge (403 responses).
# User hosts an untouched official .paf.exe once as an ASSET of a GitHub Release
# in their own PUBLIC builder repository. GitHub release assets are downloaded
# on every subsequent workflow run; the official checksum remains mandatory.
$installerVersion = '3.9.22'
$installerSha = '689456f1fb1320c45e82a077afe6b87fb388fd3f75c41d9ee9ce8d45f3966b67'
$installerFilename = "PortableApps.comInstaller_$installerVersion.paf.exe"
$releaseTag = "portableapps-installer-tool-$installerVersion"
$repoName = $env:GITHUB_REPOSITORY
if ([string]::IsNullOrWhiteSpace($repoName) -or $repoName -notmatch '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$') {
    throw 'GITHUB_REPOSITORY is missing. Run this script from your GitHub Actions builder repository.'
}

$workRoot = Join-Path $env:RUNNER_TEMP 'vscodium-paf-tools'
$downloadFile = Join-Path $workRoot $installerFilename
$toolExtract = Join-Path $workRoot 'extracted-tool'
New-Item -ItemType Directory -Force -Path $workRoot, $toolExtract, $outputRoot | Out-Null
$releaseUrl = "https://github.com/$repoName/releases/download/$releaseTag/$installerFilename"
Write-Host "Retrieving PortableApps.com Installer $installerVersion from release '$releaseTag' in $repoName"
Write-Host 'This build does not contact SourceForge.'
try {
    Invoke-WebRequest -Uri $releaseUrl -OutFile $downloadFile -MaximumRedirection 10 -TimeoutSec 120 -ErrorAction Stop
} catch {
    throw "Could not download $installerFilename from the GitHub Release '$releaseTag'. Create that release and attach the original publisher file to it first. See START-HERE.txt. Error: $($_.Exception.Message)"
}

# Verify exact PUBLISHER checksum, never a checksum from the GitHub upload.
$actualSha = (Get-FileHash -LiteralPath $downloadFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha -ne $installerSha) {
    Remove-Item -LiteralPath $downloadFile -Force
    throw "Installer checksum does not match the official publisher SHA-256. Expected $installerSha, got $actualSha. Re-download the original publisher package, do not bypass this check."
}
$stream = [System.IO.File]::OpenRead($downloadFile)
try {
    $signature = [byte[]]::new(2)
    if ($stream.Read($signature, 0, 2) -ne 2 -or $signature[0] -ne 0x4d -or $signature[1] -ne 0x5a) {
        throw 'Verified installer is not a valid Windows EXE (MZ header missing).'
    }
} finally { $stream.Dispose() }
Write-Host 'Verified against the official PortableApps.com Installer publisher SHA-256.'

# Prefer archive extraction: it does not rely on silently opening an installer GUI
# inside a GitHub Actions Windows session. Windows hosted runners commonly have
# 7-Zip preinstalled; when unavailable, fall back to the installer itself.
$sevenZipCandidates = @(
    'C:\Program Files\7-Zip\7z.exe',
    'C:\Program Files (x86)\7-Zip\7z.exe'
)
$sevenZip = $null
foreach ($candidate in $sevenZipCandidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $sevenZip = $candidate
        break
    }
}
if (-not $sevenZip) {
    $command = Get-Command '7z.exe' -ErrorAction SilentlyContinue
    if ($command) { $sevenZip = $command.Source }
}
if ($sevenZip) {
    Write-Host 'Extracting the verified official installer archive with 7-Zip.'
    & $sevenZip x -y "-o$toolExtract" $downloadFile | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "7-Zip could not extract the NSIS package (exit code $LASTEXITCODE)."
    }
} else {
    Write-Warning '7-Zip is not available; trying silent installation instead.'
}

$exeTools = @(Get-ChildItem -LiteralPath $toolExtract -Recurse -File -Filter 'PortableApps.comInstaller.exe' -ErrorAction SilentlyContinue)
if ($exeTools.Count -eq 0) {
    # Backup approach: PortableApps.com's own /S and /DESTINATION argument.
    # /DESTINATION takes a parent folder with trailing backslash.
    $installRoot = Join-Path $workRoot 'portableapps-tools'
    New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
    $dest = $installRoot.TrimEnd('\') + '\'
    Write-Host 'Attempting to install official packaging tool into temporary runner directory.'
    $toolInstaller = Start-Process -FilePath $downloadFile -ArgumentList @('/S', "/DESTINATION=$dest") -PassThru
    try {
        if (-not $toolInstaller.WaitForExit(120000)) {
            try { $toolInstaller.Kill() } catch { }
            throw 'PortableApps installer bootstrap timed out; needs a different headless install method.'
        }
        if ($toolInstaller.ExitCode -ne 0) { throw "PortableApps packager bootstrap returned code $($toolInstaller.ExitCode)" }
    } finally { $toolInstaller.Dispose() }
    $exeTools = @(Get-ChildItem -LiteralPath $installRoot -Recurse -File -Filter 'PortableApps.comInstaller.exe')
}
if ($exeTools.Count -ne 1) {
    throw "Cannot find one PortableApps.comInstaller.exe in the VERIFIED publisher package (found $($exeTools.Count)). Further investigation of installer internals is needed; do not substitute an unverified executable."
}
$packer = $exeTools[0].FullName
Write-Host 'Building a PAF from stage\VSCodiumPortable with official PortableApps.com Installer.'

# Official CLI: pass the existing portable app root as the argument. The output
# is generated next to the app's directory (normally under stage\).
$process = Start-Process -FilePath $packer -ArgumentList @('"' + $appRoot + '"') -PassThru
try {
    if (-not $process.WaitForExit(1200000)) {
        try { $process.Kill() } catch { }
        throw 'PortableApps.com Installer packaging timed out (20 minutes).'
    }
    if ($process.ExitCode -ne 0) { throw "PortableApps.com Installer build failed with exit code $($process.ExitCode)" }
} finally {
    $process.Dispose()
}
$pafs = @(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'stage') -Recurse -File -Filter '*.paf.exe')
if ($pafs.Count -ne 1) { throw "Expected one generated PAF but found $($pafs.Count). Check installer log." }
if ($pafs[0].Length -lt 10MB) { throw "Generated PAF suspiciously small: $($pafs[0].Length) bytes." }
# Read only the two-byte PE signature; the PAF can be hundreds of MB.
$signature = [byte[]]::new(2)
$signatureStream = [System.IO.File]::OpenRead($pafs[0].FullName)
try {
    if ($signatureStream.Read($signature, 0, 2) -ne 2) { throw 'Generated PAF is empty.' }
} finally { $signatureStream.Dispose() }
if ($signature[0] -ne 0x4d -or $signature[1] -ne 0x5a) { throw 'Output is not an executable (.paf.exe).' }
$destination = Join-Path $outputRoot "VSCodiumPortable_$($Version)_$($Architecture)_Community.paf.exe"
Copy-Item -LiteralPath $pafs[0].FullName -Destination $destination -Force
Write-Host "READY: $destination ($([math]::Round((Get-Item -LiteralPath $destination).Length / 1MB, 1)) MB)"
Write-Host "Generated PAF SHA256: $((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash)"
