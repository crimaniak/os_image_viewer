<#
.SYNOPSIS
  Remove the image viewer installed by install-windows.ps1.

.PARAMETER Purge
  Also remove the config file (%APPDATA%\ImageViewer).
#>
[CmdletBinding()]
param([switch]$Purge)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$Dest      = Join-Path $env:LOCALAPPDATA 'ImageViewer'
$ConfigDir = Join-Path $env:APPDATA 'ImageViewer'
$ProgId    = 'ImageViewer.Image'
$AppKey    = 'ImageViewer'
$Extensions = '.png', '.apng', '.jpg', '.jpeg', '.jpe', '.jfif', '.pjpeg', '.pjp',
              '.gif', '.webp', '.svg', '.bmp', '.ico', '.avif'

$HKCU = [Microsoft.Win32.Registry]::CurrentUser

function Remove-Tree([string]$Key) {
  $k = $HKCU.OpenSubKey($Key)
  if ($k) { $k.Close(); Write-Host "Removing HKCU\$Key"; $HKCU.DeleteSubKeyTree($Key, $false) }
}
function Remove-Value([string]$Key, [string]$Name) {
  $k = $HKCU.OpenSubKey($Key, $true)
  if ($k) { try { $k.DeleteValue($Name, $false) } finally { $k.Close() } }
}

Remove-Tree "Software\Classes\$ProgId"
Remove-Tree 'Software\Classes\Applications\ImageViewer.exe'
Remove-Tree "Software\$AppKey"
Remove-Value 'Software\RegisteredApplications' $AppKey
foreach ($e in $Extensions) { Remove-Value "Software\Classes\$e\OpenWithProgids" $ProgId }

Add-Type -Namespace ImageViewerSetup -Name Shell -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
[ImageViewerSetup.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

if (Test-Path -LiteralPath $Dest) {
  Write-Host "Removing $Dest"
  try { Remove-Item -LiteralPath $Dest -Recurse -Force }
  catch { Write-Warning "Some files are in use (close Image Viewer windows and run again): $($_.Exception.Message)" }
}
if ($Purge -and (Test-Path -LiteralPath $ConfigDir)) {
  Write-Host "Removing $ConfigDir"
  Remove-Item -LiteralPath $ConfigDir -Recurse -Force
}

Write-Host 'Done. If Image Viewer was the default app, Windows will ask which app to use next time.'
