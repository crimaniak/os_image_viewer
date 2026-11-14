<#
.SYNOPSIS
  Install the image viewer for the current user (no admin rights, no Python).

.DESCRIPTION
  Installs to %LOCALAPPDATA%\ImageViewer:
    viewer\            viewer.html, viewer.css, viewer.js
    open-image.ps1     launcher
    open-image.cmd     launcher wrapper for terminal use
    ImageViewer.exe    "Open with" stub, compiled here with the built-in csc.exe
  Registers (HKCU only):
    ProgID ImageViewer.Image, Applications\ImageViewer.exe,
    OpenWithProgids for each image extension, and a RegisteredApplications
    entry so Image Viewer appears in Settings > Default apps.

.PARAMETER Default
  Open Settings > Default apps for Image Viewer afterwards. Windows does not let
  scripts change the default app; you confirm it there.

.PARAMETER Browser
  Always use this browser (exe name or full path), e.g. chrome, msedge, firefox.
  Checked first, then written to %APPDATA%\ImageViewer\config.json.
  -Browser auto removes the setting (use the default browser).

.PARAMETER ListBrowsers
  Show the browsers found on this system and exit.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Default
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install-windows.ps1 -ListBrowsers
#>
[CmdletBinding()]
param(
  [switch]$Default,
  [string]$Browser,
  [switch]$ListBrowsers
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$Src       = Split-Path -Parent $PSScriptRoot
$Dest      = Join-Path $env:LOCALAPPDATA 'ImageViewer'
$ConfigDir = Join-Path $env:APPDATA 'ImageViewer'
$ProgId    = 'ImageViewer.Image'
$AppKey    = 'ImageViewer'
$Extensions = '.png', '.apng', '.jpg', '.jpeg', '.jpe', '.jfif', '.pjpeg', '.pjp',
              '.gif', '.webp', '.svg', '.bmp', '.ico', '.avif'

foreach ($f in 'viewer\viewer.html', 'viewer\viewer.css', 'viewer\viewer.js',
               'launchers\windows\open-image.ps1', 'launchers\windows\open-image.cmd',
               'launchers\windows\ImageViewer.cs') {
  if (-not (Test-Path -LiteralPath (Join-Path $Src $f))) { throw "Missing $Src\$f" }
}

$Launcher = Join-Path $Src 'launchers\windows\open-image.ps1'
if ($ListBrowsers) { & $Launcher -ListBrowsers; return }

# Check the browser before changing anything.
$BrowserInfo = $null
if ($PSBoundParameters.ContainsKey('Browser') -and $Browser -ne 'auto') {
  try {
    $BrowserInfo = (& $Launcher -CheckBrowser $Browser) -join "`n"
  } catch {
    Write-Host "Browser not usable: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Run install-windows.ps1 -ListBrowsers to see what is installed."
    exit 1
  }
}

# ----------------------------------------------------------------- files ----

Write-Host "Installing to $Dest"
New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'viewer') | Out-Null
Copy-Item -Force -Path (Join-Path $Src 'viewer\*') -Destination (Join-Path $Dest 'viewer')
Copy-Item -Force -LiteralPath (Join-Path $Src 'launchers\windows\open-image.ps1'),
                              (Join-Path $Src 'launchers\windows\open-image.cmd') -Destination $Dest
# Drop "downloaded from the internet" marks so the launcher runs without prompts.
Get-ChildItem -LiteralPath $Dest -Recurse -File | Unblock-File

# ------------------------------------------------------------ exe stub ----

$exe = Join-Path $Dest 'ImageViewer.exe'
$csc = @(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

$useStub = $false
if ($csc) {
  Write-Host 'Compiling ImageViewer.exe'
  $out = & $csc /nologo /target:winexe /optimize+ "/out:$exe" (Join-Path $Src 'launchers\windows\ImageViewer.cs') 2>&1
  if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exe)) { $useStub = $true }
  else { Write-Warning "csc.exe failed; falling back to PowerShell directly.`n$out" }
} else {
  Write-Warning 'csc.exe (.NET Framework 4) not found; falling back to PowerShell directly.'
}

if ($useStub) {
  $command = '"' + $exe + '" "%1"'
} else {
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $command = '"' + $ps + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
             (Join-Path $Dest 'open-image.ps1') + '" "%1"'
}

# ------------------------------------------------------------- registry ----

$HKCU = [Microsoft.Win32.Registry]::CurrentUser

function Set-Reg([string]$Key, [string]$Name, $Value,
                 [Microsoft.Win32.RegistryValueKind]$Kind = [Microsoft.Win32.RegistryValueKind]::String) {
  $k = $HKCU.CreateSubKey($Key)
  try { $k.SetValue($Name, $Value, $Kind) } finally { $k.Close() }
}

Write-Host 'Registering file associations (current user)'

# ProgID used by "Open with" and as the default handler.
$pk = "Software\Classes\$ProgId"
Set-Reg $pk '' 'Image (Image Viewer)'
Set-Reg $pk 'FriendlyTypeName' 'Image'
Set-Reg "$pk\Application" 'ApplicationName' 'Image Viewer'
Set-Reg "$pk\shell" '' 'open'
Set-Reg "$pk\shell\open" 'FriendlyAppName' 'Image Viewer'
Set-Reg "$pk\shell\open\command" '' $command

# Applications\ImageViewer.exe: name and supported types for the "Open with" dialog.
if ($useStub) {
  $ak = 'Software\Classes\Applications\ImageViewer.exe'
  Set-Reg $ak 'FriendlyAppName' 'Image Viewer'
  Set-Reg "$ak\shell\open\command" '' $command
  foreach ($e in $Extensions) { Set-Reg "$ak\SupportedTypes" $e '' }
}

# Offer the ProgID for every extension (does not change the current default).
foreach ($e in $Extensions) {
  Set-Reg "Software\Classes\$e\OpenWithProgids" $ProgId ([byte[]]@()) ([Microsoft.Win32.RegistryValueKind]::None)
}

# Capabilities -> listed in Settings > Default apps.
$ck = "Software\$AppKey\Capabilities"
Set-Reg $ck 'ApplicationName' 'Image Viewer'
Set-Reg $ck 'ApplicationDescription' 'Browser-based image viewer'
foreach ($e in $Extensions) { Set-Reg "$ck\FileAssociations" $e $ProgId }
Set-Reg 'Software\RegisteredApplications' $AppKey $ck

# Tell Explorer that associations changed.
Add-Type -Namespace ImageViewerSetup -Name Shell -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
[ImageViewerSetup.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

# --------------------------------------------------------------- config ----

if ($Browser -eq 'auto') {
  Remove-Item -Force -LiteralPath (Join-Path $ConfigDir 'config.json') -ErrorAction SilentlyContinue
  Write-Host 'Browser setting removed: the default browser is used.'
} elseif ($PSBoundParameters.ContainsKey('Browser')) {
  New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
  $json = @{ browser = $Browser } | ConvertTo-Json
  [IO.File]::WriteAllText((Join-Path $ConfigDir 'config.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "Browser set to: $BrowserInfo"
  Write-Host "  (saved in $ConfigDir\config.json)"
}

if ($Default) {
  Write-Host 'Opening Settings > Default apps. Choose Image Viewer for the image types there.'
  Start-Process "ms-settings:defaultapps?registeredAppUser=$AppKey"
}

Write-Host 'Done. Right-click an image > Open with > Image Viewer.'
