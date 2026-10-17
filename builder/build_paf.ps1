# This script is ADDITIVE: it does not alter the existing portable ZIP builder.
# It downloads PortableApps.com Installer from the publisher, checks the pinned
# SHA256, installs this development tool on the temporary GitHub runner, then
# builds the .paf.exe from the already-staged App/Data/Other portable layout.
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
RemoveDataDirectory=false
RemoveOtherDirectory=true
'@
Set-Content -LiteralPath (Join-Path $infoRoot 'installer.ini') -Value $installerIni -Encoding ascii

# Official stable Installer version and its SHA-256 as published on SourceForge.
# Both are intentionally pinned. Update both from the official publisher when
# newer versions appear; do not bypass integrity verification on failure.
$installerVersion = '3.9.22'
$installerSha = '689456f1fb1320c45e82a077afe6b87fb388fd3f75c41d9ee9ce8d45f3966b67'
$installerFilename = "PortableApps.comInstaller_$installerVersion.paf.exe"
$installerUrl = "https://downloads.sourceforge.net/project/portableapps/PortableApps.com%20Installer/$installerFilename?download"
$workRoot = Join-Path $env:RUNNER_TEMP 'vscodium-paf-tools'
$downloadFile = Join-Path $workRoot $installerFilename
$installRoot = Join-Path $workRoot 'portableapps-tools'
New-Item -ItemType Directory -Force -Path $workRoot, $installRoot, $outputRoot | Out-Null
Write-Host "Downloading official PortableApps.com Installer $installerVersion"
Invoke-WebRequest -Uri $installerUrl -OutFile $downloadFile -MaximumRedirection 10 -ErrorAction Stop
$actualSha = (Get-FileHash -LiteralPath $downloadFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha -ne $installerSha) {
    throw "Official installer checksum mismatch ($actualSha). Stopping safely."
}
Write-Host 'Official PortableApps.com Installer SHA-256 verified.'

# The source package is itself a .paf.exe. Install the packager to a temporary
# directory on this short-lived GitHub Windows machine, not to the user's PC.
# PortableApps.com's NSIS installers support /S (silent) and /DESTINATION.
Write-Host 'Unpacking PortableApps.com Installer on the temporary GitHub runner.'
$toolInstaller = Start-Process -FilePath $downloadFile -ArgumentList @('/S', "/DESTINATION=$installRoot\") -PassThru
try {
    if (-not $toolInstaller.WaitForExit(180000)) {
        try { $toolInstaller.Kill() } catch { }
        throw 'The PortableApps.com Installer setup timed out (3 minutes).'
    }
    if ($toolInstaller.ExitCode -ne 0) { throw "PortableApps.com Installer setup failed with exit code $($toolInstaller.ExitCode)" }
} finally {
    $toolInstaller.Dispose()
}
$exeTools = @(Get-ChildItem -LiteralPath $installRoot -Recurse -File -Filter 'PortableApps.comInstaller.exe')
if ($exeTools.Count -ne 1) {
    throw "Expected one installed PortableApps.comInstaller.exe; found $($exeTools.Count)."
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
