# Builds Audio Mixer for Windows with the C# compiler that ships with Windows
# (no Visual Studio or .NET SDK needed) and packages a portable zip plus an installer.
#
#   .\build.ps1                         unsigned build into ..\dist\windows
#   .\build.ps1 -SignThumbprint <sha1>  also signs the app, uninstaller and installer
#   .\build.ps1 -SkipInstaller          app and zip only
param(
    [string]$Version = '1.0.0',
    [string]$SignThumbprint = '',
    [string]$TimestampUrl = 'http://time.certum.pl',
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
$work = Join-Path $repo 'build\win'
$dist = Join-Path $repo 'dist\windows'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $framework 'csc.exe'
if (-not (Test-Path $csc)) { throw "C# compiler not found at $csc" }

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work, $dist | Out-Null

function Invoke-Compile([string]$output, [string]$icon) {
    $arguments = @(
        '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu', '/warnaserror-',
        "/out:$output",
        "/win32manifest:$(Join-Path $here 'app.manifest')",
        "/r:$(Join-Path $framework 'WPF\PresentationFramework.dll')",
        "/r:$(Join-Path $framework 'WPF\PresentationCore.dll')",
        "/r:$(Join-Path $framework 'WPF\WindowsBase.dll')",
        '/r:System.Xaml.dll', '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll',
        "/resource:$(Join-Path $here 'src\Theme.xaml'),AudioMixer.Theme.xaml",
        "/resource:$(Join-Path $here 'src\MainWindow.xaml'),AudioMixer.MainWindow.xaml"
    )
    if ($icon) { $arguments += "/win32icon:$icon" }
    $arguments += (Get-ChildItem (Join-Path $here 'src\*.cs') | ForEach-Object { $_.FullName })
    $arguments += $versionFile
    & $csc $arguments
    if ($LASTEXITCODE -ne 0) { throw "Compile failed ($LASTEXITCODE)" }
}

function Find-Tool([string]$name, [string]$filter) {
    $onPath = Get-Command $name -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $roots = @("$env:LOCALAPPDATA\electron-builder\Cache", "${env:ProgramFiles(x86)}\Windows Kits\10\bin", "${env:ProgramFiles(x86)}\NSIS")
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $found = Get-ChildItem $root -Recurse -Filter $name -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like $filter } | Sort-Object FullName -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

$signtool = $null
if ($SignThumbprint) {
    $signtool = Find-Tool 'signtool.exe' '*x64*'
    if (-not $signtool) { throw 'signtool.exe not found; cannot sign.' }
}

function Invoke-Sign([string]$file) {
    if (-not $SignThumbprint) { return }
    & $signtool sign /sha1 $SignThumbprint /tr $TimestampUrl /td sha256 /fd sha256 /d 'Audio Mixer' $file
    if ($LASTEXITCODE -ne 0) { throw "Signing failed for $file" }
    & $signtool verify /pa /all /tw $file
    if ($LASTEXITCODE -ne 0) { throw "Signature did not verify for $file" }
}

# One source of truth for the version: the -Version parameter.
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.2.3 (got '$Version')" }
$versionFile = Join-Path $work 'Version.cs'
@"
[assembly: System.Reflection.AssemblyVersion("$Version.0")]
[assembly: System.Reflection.AssemblyFileVersion("$Version.0")]
[assembly: System.Reflection.AssemblyInformationalVersion("$Version")]
namespace AudioMixer { internal static class BuildInfo { public const string Version = "$Version"; } }
"@ | Set-Content -Encoding utf8 $versionFile

# The icon is drawn by the app itself, so compile once to render it, then again to embed it.
$stage = Join-Path $work 'stage'
New-Item -ItemType Directory -Force $stage | Out-Null
$bootstrap = Join-Path $work 'bootstrap.exe'
$icon = Join-Path $work 'AudioMixer.ico'
Invoke-Compile $bootstrap ''
$render = Start-Process -FilePath $bootstrap -ArgumentList '--make-icon', "`"$icon`"" -Wait -PassThru
if ($render.ExitCode -ne 0 -or -not (Test-Path $icon)) { throw "Icon was not rendered (exit $($render.ExitCode))." }

$app = Join-Path $stage 'AudioMixer.exe'
Invoke-Compile $app $icon
Invoke-Sign $app

$zip = Join-Path $dist "Audio-Mixer-$Version-windows.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path $app -DestinationPath $zip
$outputs = @($zip)

if (-not $SkipInstaller) {
    $makensis = Find-Tool 'makensis.exe' '*Bin*'
    if (-not $makensis) { $makensis = Find-Tool 'makensis.exe' '*' }
    if (-not $makensis) {
        Write-Warning 'NSIS (makensis.exe) not found; skipping the installer.'
    } else {
        $script = Join-Path $here 'installer.nsi'
        $common = @('/V2', "/DVERSION=$Version", "/DSTAGE=$stage", "/DICON=$icon")
        # NSIS writes the uninstaller at install time, which would leave it unsigned. Build a
        # throwaway installer that only emits the uninstaller, sign that, then package it.
        $stub = Join-Path $work 'make-uninstaller.exe'
        & $makensis ($common + @('/DUNINSTALLER_ONLY', "/DOUTPUT=$stub", $script))
        if ($LASTEXITCODE -ne 0) { throw 'makensis failed (uninstaller pass)' }
        Start-Process -FilePath $stub -Wait
        $uninstaller = Join-Path $work 'Uninstall.exe'
        if (-not (Test-Path $uninstaller)) { throw 'Uninstaller was not produced.' }
        Invoke-Sign $uninstaller
        Copy-Item $uninstaller (Join-Path $stage 'Uninstall.exe') -Force

        $setup = Join-Path $dist "Audio-Mixer-Setup-$Version.exe"
        Remove-Item $setup -ErrorAction SilentlyContinue
        & $makensis ($common + @("/DOUTPUT=$setup", $script))
        if ($LASTEXITCODE -ne 0) { throw 'makensis failed (installer pass)' }
        Invoke-Sign $setup
        $outputs += $setup
    }
}

$sums = foreach ($file in $outputs) {
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
    "$hash  $(Split-Path -Leaf $file)"
}
# LF line endings so `sha256sum -c` also works on macOS and Linux.
[IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS.txt'), (($sums -join "`n") + "`n"), [Text.Encoding]::ASCII)

Write-Host ''
Write-Host "Built Audio Mixer $Version for Windows$(if ($SignThumbprint) { ' (signed)' } else { ' (unsigned)' }):"
$outputs | ForEach-Object { Write-Host "  $_  ($([math]::Round((Get-Item $_).Length / 1KB)) KB)" }
