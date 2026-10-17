# Runs on the Windows GitHub Actions runner after Python has staged the official ZIP.
# Uses VSCodium's ORIGINAL Windows code.ico, pinned to the selected stable release.
# No guessed icon or lossy ExtractAssociatedIcon step.
$ErrorActionPreference = 'Stop'
$stage = Join-Path (Get-Location) 'stage\VSCodiumPortable'
$app = Join-Path $stage 'App\VSCodium\VSCodium.exe'
$appInfo = Join-Path $stage 'App\AppInfo'
$source = Join-Path (Get-Location) 'builder\VSCodiumPortable.cs'
$launcher = Join-Path $stage 'VSCodiumPortable.exe'
$buildInfo = Join-Path $stage 'Other\Source\Build-Information.txt'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $app)) { throw "Missing official VSCodium executable: $app" }
if (!(Test-Path -LiteralPath $source)) { throw 'Missing launcher C# source' }
if (!(Test-Path -LiteralPath $compiler)) { throw 'Missing Windows .NET Framework C# compiler' }
if (!(Test-Path -LiteralPath $buildInfo)) { throw 'Missing checked release information' }
New-Item -ItemType Directory -Force -Path $appInfo | Out-Null

# The builder previously checked the release's official GitHub API SHA-256
# and wrote its version into this generated metadata file.
$releaseInfo = Get-Content -LiteralPath $buildInfo -Raw
$versionLine = [regex]::Match($releaseInfo, '(?m)^Version: ([0-9]+\.[0-9]+\.[0-9]+)\s*$')
if (!$versionLine.Success) { throw 'Stable VSCodium version not found in build metadata' }
$version = $versionLine.Groups[1].Value

# Official source tree includes the multi-resolution Windows icon, pinned to
# exactly the selected stable version (not latest/master).
$url = "https://raw.githubusercontent.com/VSCodium/vscodium/$version/src/stable/resources/win32/code.ico"
$icoPath = Join-Path $appInfo 'appicon.ico'
Write-Host "Retrieving official VSCodium Windows icon for version $version"
Invoke-WebRequest -Uri $url -OutFile $icoPath -ErrorAction Stop

# Windows icon container must be 00 00 01 00 followed by count of images.
$iconBytes = [System.IO.File]::ReadAllBytes($icoPath)
if ($iconBytes.Length -lt 4096 -or $iconBytes.Length -gt 2097152) {
    throw "Official icon has unexpected length: $($iconBytes.Length) bytes"
}
if ($iconBytes[0] -ne 0 -or $iconBytes[1] -ne 0 -or
    $iconBytes[2] -ne 1 -or $iconBytes[3] -ne 0) {
    throw 'Downloaded file is not a valid Windows ICO container'
}
$iconCount = [int]$iconBytes[4] + (256 * [int]$iconBytes[5])
if ($iconCount -lt 2) { throw 'Official icon does not contain multiple resolutions' }
Write-Host "Official icon downloaded: $($iconBytes.Length) bytes; $iconCount icon images"

# Render PortableApps icons from the official ICO, choosing the closest built-in
# source image at each size; NEVER re-extract from VSCodium.exe.
Add-Type -AssemblyName System.Drawing
foreach ($size in @(16, 32, 128)) {
    $vscodiumIcon = [System.Drawing.Icon]::new($icoPath, [int]$size, [int]$size)
    try {
        $bmp = [System.Drawing.Bitmap]::new([int]$size, [int]$size)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.DrawIcon($vscodiumIcon, [System.Drawing.Rectangle]::new(0, 0, [int]$size, [int]$size))
            } finally { $graphics.Dispose() }
            $bmp.Save((Join-Path $appInfo "appicon_$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $bmp.Dispose() }
    } finally { $vscodiumIcon.Dispose() }
}

# Embed the SAME source ICO in the community launcher executable.
& $compiler /nologo /target:winexe "/out:$launcher" "/win32icon:$icoPath" /reference:System.Windows.Forms.dll $source
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $launcher)) {
    throw 'Compilation of VSCodiumPortable.exe with official icon failed'
}
Write-Host 'Compiled VSCodiumPortable.exe with original official VSCodium icon and PortableApps icon sizes.'
