# Runs on the Windows GitHub Actions runner after Python has staged the official ZIP.
# Uses the already installed .NET Framework compiler, with no outside downloads.
$ErrorActionPreference = 'Stop'
$stage = Join-Path (Get-Location) 'stage\VSCodiumPortable'
$app = Join-Path $stage 'App\VSCodium\VSCodium.exe'
$appInfo = Join-Path $stage 'App\AppInfo'
$source = Join-Path (Get-Location) 'builder\VSCodiumPortable.cs'
$launcher = Join-Path $stage 'VSCodiumPortable.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $app)) { throw "Missing official VSCodium executable: $app" }
if (!(Test-Path -LiteralPath $source)) { throw 'Missing launcher C# source' }
if (!(Test-Path -LiteralPath $compiler)) { throw 'Missing Windows .NET Framework C# compiler' }
New-Item -ItemType Directory -Force -Path $appInfo | Out-Null

Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($app)
if ($null -eq $icon) { throw 'Could not extract an icon from the official VSCodium executable' }
try {
    $icoPath = Join-Path $appInfo 'appicon.ico'
    $stream = [System.IO.File]::Open($icoPath, [System.IO.FileMode]::Create)
    try { $icon.Save($stream) } finally { $stream.Dispose() }

    foreach ($size in @(16, 32, 128)) {
        $bmp = [System.Drawing.Bitmap]::new([int]$size, [int]$size)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.DrawIcon($icon, [System.Drawing.Rectangle]::new(0, 0, [int]$size, [int]$size))
            } finally { $graphics.Dispose() }
            $bmp.Save((Join-Path $appInfo "appicon_$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $bmp.Dispose() }
    }
} finally { $icon.Dispose() }

& $compiler /nologo /target:winexe "/out:$launcher" "/win32icon:$icoPath" /reference:System.Windows.Forms.dll $source
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $launcher)) { throw 'Compilation of VSCodiumPortable.exe failed' }
Write-Host 'Compiled community launcher and generated PortableApps icons.'
