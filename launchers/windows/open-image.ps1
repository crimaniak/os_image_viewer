<#
.SYNOPSIS
  Image Viewer launcher for Windows (Windows PowerShell 5.1 or PowerShell 7; no Python).

.DESCRIPTION
  Opens each image in the browser-based viewer, in a window without tabs where the
  browser allows it:
    Chromium family (Chrome, Edge, Brave, Vivaldi, Opera) -> --app=<url>
    Firefox family -> dedicated profile whose userChrome.css hides tabs and toolbars
    anything else  -> plain new window

  Browser choice, in order:
    1. $env:IMAGE_VIEWER_BROWSER (exe name or full path)
    2. "browser" in %APPDATA%\ImageViewer\config.json
    3. the default web browser
    4. the first installed of Chrome, Edge, Brave, Vivaldi, Firefox

.EXAMPLE
  open-image.ps1 C:\Pictures\photo.jpg
.EXAMPLE
  open-image.ps1 -DryRun C:\Pictures\photo.jpg   # print the command, don't run it
.EXAMPLE
  open-image.ps1 -ListBrowsers                    # browsers usable as -Browser values
.EXAMPLE
  open-image.ps1 -CheckBrowser chrome             # check a value; error if unusable
#>
[CmdletBinding(PositionalBinding = $false)]   # bare arguments all go to -Path
param(
  [switch]$DryRun,
  [switch]$ListBrowsers,
  [string]$CheckBrowser,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Path
)

Set-StrictMode -Version 2
$CheckGiven = $PSBoundParameters.ContainsKey('CheckBrowser')
$ErrorActionPreference = 'Stop'

$AppData   = Join-Path $env:LOCALAPPDATA 'ImageViewer'
$ConfigDir = Join-Path $env:APPDATA 'ImageViewer'

# ---------------------------------------------------------------- URLs ----

# Absolute Windows path (drive or UNC) -> file:// URL, each segment percent-encoded.
function ConvertTo-FileUrl([string]$FullPath) {
  if ($FullPath -match '^[A-Za-z][A-Za-z0-9+.-]+://') { return $FullPath }   # already a URL
  $p = $FullPath
  if ($p.StartsWith('\\?\UNC\')) { $p = '\\' + $p.Substring(8) }
  elseif ($p.StartsWith('\\?\')) { $p = $p.Substring(4) }
  $p = $p -replace '\\', '/'
  if ($p.StartsWith('//')) {                                   # \\host\share\...
    $parts = $p.Substring(2).Split('/')
    $enc = @($parts | Select-Object -Skip 1 | ForEach-Object { [Uri]::EscapeDataString($_) })
    return 'file://' + $parts[0] + '/' + ($enc -join '/')
  }
  $parts = $p.Split('/')                                       # C:/dir/file
  $enc = @($parts[0]) + @($parts | Select-Object -Skip 1 | ForEach-Object { [Uri]::EscapeDataString($_) })
  return 'file:///' + ($enc -join '/')
}

function Get-ViewerUrl([string]$ViewerDir, [string]$Image) {
  $url = ConvertTo-FileUrl ($ViewerDir.TrimEnd('\', '/') + '\viewer.html')
  if ($Image) { $url += '?src=' + [Uri]::EscapeDataString((ConvertTo-FileUrl $Image)) }
  return $url
}

# Quote arguments for a Windows command line (CommandLineToArgvW rules).
function ConvertTo-ArgString([string[]]$ArgList) {
  $quoted = foreach ($a in $ArgList) {
    if ($a -eq '') { '""' }
    elseif ($a -notmatch '[\s"]') { $a }
    else { '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
  }
  return ($quoted -join ' ')
}

# ------------------------------------------------------------ browsers ----

# First token of a shell command line, with environment variables expanded.
function Get-CommandExe([string]$CommandLine) {
  $c = [Environment]::ExpandEnvironmentVariables($CommandLine).Trim()
  if ($c.StartsWith('"')) {
    $end = $c.IndexOf('"', 1)
    if ($end -gt 1) { return $c.Substring(1, $end - 1) }
  }
  $i = $c.ToLowerInvariant().IndexOf('.exe')
  if ($i -ge 0) { return $c.Substring(0, $i + 4) }
  return ($c -split '\s+')[0]
}

function Get-AppPath([string]$ExeName) {
  foreach ($root in 'HKEY_CURRENT_USER', 'HKEY_LOCAL_MACHINE') {
    try {
      $v = [Microsoft.Win32.Registry]::GetValue(
        "$root\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExeName", '', $null)
    } catch { $v = $null }                                   # no registry (not Windows)
    if ($v) {
      $v = [Environment]::ExpandEnvironmentVariables(([string]$v).Trim('"'))
      if (Test-Path -LiteralPath $v) { return $v }
    }
  }
  return $null
}

# Exe name or path -> full path, or $null.
function Resolve-Browser([string]$Name) {
  if (-not $Name) { return $null }
  $Name = [Environment]::ExpandEnvironmentVariables($Name.Trim().Trim('"'))
  if ($Name -match '[\\/:]') {                            # a path, not a name
    if (Test-Path -LiteralPath $Name -PathType Leaf) { return $Name }
    return $null
  }
  $exe = if ($Name -like '*.exe') { $Name } else { "$Name.exe" }
  $p = Get-AppPath $exe
  if ($p) { return $p }
  $cmd = Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  return $null
}

function Get-DefaultBrowser {
  $base = 'HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http'
  foreach ($k in 'UserChoiceLatest', 'UserChoice') {
    $progId = [Microsoft.Win32.Registry]::GetValue("$base\$k", 'ProgId', $null)
    if (-not $progId) { continue }
    $key = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey("$progId\shell\open\command")
    if (-not $key) { continue }
    try { $cmd = $key.GetValue('') } finally { $key.Close() }
    if ($cmd) {
      $exe = Get-CommandExe $cmd
      if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
    }
  }
  return $null
}

function Get-FallbackBrowser {
  foreach ($exe in 'chrome.exe', 'msedge.exe', 'brave.exe', 'vivaldi.exe', 'firefox.exe') {
    $p = Get-AppPath $exe
    if ($p) { return $p }
  }
  $edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
  if (Test-Path -LiteralPath $edge) { return $edge }
  return $null
}

function Get-ConfiguredBrowser {
  if ($env:IMAGE_VIEWER_BROWSER) { return $env:IMAGE_VIEWER_BROWSER }
  $cfg = Join-Path $ConfigDir 'config.json'
  if (Test-Path -LiteralPath $cfg) {
    $json = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
    if ($json.PSObject.Properties['browser'] -and $json.browser) { return [string]$json.browser }
  }
  return $null
}

function Get-BrowserFamily([string]$Exe) {
  $n = [IO.Path]::GetFileNameWithoutExtension($Exe).ToLowerInvariant()
  if ($n -match 'chrome|chromium|msedge|edge|brave|vivaldi|opera|yandex') { return 'chromium' }
  if ($n -match 'firefox|librewolf|waterfox|floorp') { return 'firefox' }
  return 'generic'
}

# -------------------------------------------------- checking and listing ----

function Get-WindowMode([string]$Exe) {
  switch (Get-BrowserFamily $Exe) {
    'chromium' { return 'app window, no tabs' }
    'firefox'  { return 'own Firefox profile, no tabs' }
    default    { return 'normal browser window' }
  }
}

# Browser value -> exe path; throws a readable message when it is unusable.
function Test-Browser([string]$Value) {
  if (-not $Value -or -not $Value.Trim()) { throw 'Empty browser value.' }
  $exe = Resolve-Browser $Value
  if (-not $exe) { throw "Browser not found: $Value" }
  return $exe
}

# Picks the browser like a launch does. Returns @{ Path; From }; Path is $null
# (and From says why) when nothing usable is found.
function Select-Browser {
  $configured = Get-ConfiguredBrowser
  if ($configured) {
    $from = if ($env:IMAGE_VIEWER_BROWSER) { 'IMAGE_VIEWER_BROWSER environment variable' }
            else { "config file $ConfigDir\config.json" }
    $p = Resolve-Browser $configured
    if ($p) { return @{ Path = $p; From = $from } }
    return @{ Path = $null; From = "${from}: browser not found: $configured" }
  }
  $p = $null
  try { $p = Get-DefaultBrowser } catch { $p = $null }
  if ($p) { return @{ Path = $p; From = 'system default' } }
  $p = Get-FallbackBrowser
  if ($p) { return @{ Path = $p; From = 'first installed browser' } }
  return @{ Path = $null; From = 'no supported browser found' }
}

# Browsers registered with Windows (Settings > Default apps lists the same ones).
function Get-RegisteredBrowsers {
  $views = @(
    @([Microsoft.Win32.RegistryHive]::CurrentUser,  [Microsoft.Win32.RegistryView]::Default),
    @([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64),
    @([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry32))
  foreach ($v in $views) {
    try { $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($v[0], $v[1]) } catch { continue }
    $smi = $base.OpenSubKey('SOFTWARE\Clients\StartMenuInternet')
    if ($smi) {
      foreach ($name in $smi.GetSubKeyNames()) {
        $key = $smi.OpenSubKey($name)
        $cmdKey = $smi.OpenSubKey("$name\shell\open\command")
        $display = $name; $cmd = $null
        if ($key) { $d = $key.GetValue(''); if ($d) { $display = [string]$d }; $key.Close() }
        if ($cmdKey) { $cmd = [string]$cmdKey.GetValue(''); $cmdKey.Close() }
        if ($cmd) {
          $exe = Get-CommandExe $cmd
          if (Test-Path -LiteralPath $exe -PathType Leaf) { [pscustomobject]@{ Name = $display; Path = $exe } }
        }
      }
      $smi.Close()
    }
    $base.Close()
  }
}

# One row per installed browser: Value (what to pass as -Browser), Name, Window, Note.
function Get-BrowserList($Registered, [string]$DefaultPath, [string]$InUsePath) {
  $found = @()
  foreach ($exe in 'chrome.exe', 'msedge.exe', 'brave.exe', 'vivaldi.exe', 'opera.exe', 'firefox.exe') {
    $p = Get-AppPath $exe
    if ($p) { $found += [pscustomobject]@{ Name = ''; Path = $p } }
  }
  $found += @($Registered)
  $rows = @(); $seen = @{}
  foreach ($b in $found) {
    if (-not $b) { continue }
    $key = $b.Path.ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
      if ($b.Name -and -not $seen[$key].Name) { $seen[$key].Name = $b.Name }
      continue
    }
    $short = [IO.Path]::GetFileNameWithoutExtension($b.Path)
    $resolved = Resolve-Browser $short
    $value = if ($resolved -and $resolved -ieq $b.Path) { $short } else { $b.Path }
    $notes = @()
    if ($DefaultPath -and $DefaultPath -ieq $b.Path) { $notes += 'system default' }
    if ($InUsePath -and $InUsePath -ieq $b.Path) { $notes += 'in use' }
    $row = [pscustomobject]@{
      Value = $value; Name = $b.Name; Window = (Get-WindowMode $b.Path); Note = ($notes -join ', ')
    }
    $seen[$key] = $row
    $rows += $row
  }
  return $rows
}

function Format-BrowserTable($Rows) {
  $Rows = @($Rows | Where-Object { $_ })
  if ($Rows.Count -eq 0) { return '  (none found)' }
  $cols = 'Value', 'Name', 'Window', 'Note'
  $w = @{}
  foreach ($c in $cols) {
    $w[$c] = $c.Length
    foreach ($r in $Rows) {
      $s = [string]$r.$c; if ($s -match ' ' -and $c -eq 'Value') { $s = '"' + $s + '"' }
      if ($s.Length -gt $w[$c]) { $w[$c] = $s.Length }
    }
  }
  $fmt = { param($a, $b, $c, $d) ('  ' + $a.PadRight($w['Value']) + '  ' + $b.PadRight($w['Name']) + '  ' +
                                  $c.PadRight($w['Window']) + '  ' + $d).TrimEnd() }
  $lines = @(& $fmt 'VALUE' 'NAME' 'WINDOW' 'NOTE')
  foreach ($r in $Rows) {
    $v = [string]$r.Value; if ($v -match ' ') { $v = '"' + $v + '"' }
    $lines += & $fmt $v ([string]$r.Name) ([string]$r.Window) ([string]$r.Note)
  }
  return $lines
}

function Show-BrowserList {
  $pick = Select-Browser
  $default = $null
  try { $default = Get-DefaultBrowser } catch { $default = $null }
  $registered = @()
  try { $registered = @(Get-RegisteredBrowsers) } catch { $registered = @() }
  Write-Output 'Browsers found (use the first column as the -Browser value):'
  Write-Output ''
  Format-BrowserTable (Get-BrowserList $registered $default $pick.Path)
  Write-Output ''
  if ($pick.Path) { Write-Output "In use now: $($pick.Path) ($($pick.From))" }
  else { Write-Output "In use now: none ($($pick.From))" }
  Write-Output 'Any other browser works too: give the full path to its .exe.'
}

function Show-BrowserCheck([string]$Value) {
  $exe = Test-Browser $Value
  Write-Output "$Value -> $exe ($(Get-WindowMode $exe))"
  if ((Get-BrowserFamily $exe) -eq 'generic') {
    Write-Output 'note: not a known browser; it gets the viewer URL as its only argument'
  }
}

# ------------------------------------------------------- firefox profile ----

function Initialize-FirefoxProfile([string]$Dir) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'chrome') | Out-Null
  $userJs = @'
// Written by open-image; regenerated on every launch.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.tabs.inTitlebar", 0);
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.startup.upgradeDialog.enabled", false);
user_pref("browser.startup.page", 0);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.tabs.closeWindowWithLastTab", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("app.normandy.enabled", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.defaultbrowser.notificationbar", false);
'@
  $css = @'
/* Written by open-image: hide tabs, toolbars and sidebars. */
#TabsToolbar,
#nav-bar,
#PersonalToolbar,
#sidebar-main,
#sidebar-box,
#sidebar-splitter,
#sidebar-launcher-splitter {
  visibility: collapse !important;
}
'@
  [IO.File]::WriteAllText((Join-Path $Dir 'user.js'), $userJs, $utf8)
  [IO.File]::WriteAllText((Join-Path $Dir 'chrome\userChrome.css'), $css, $utf8)
}

# ----------------------------------------------------------------- main ----

function Find-ViewerDir {
  $candidates = @()
  if ($env:IMAGE_VIEWER_DIR) { $candidates += $env:IMAGE_VIEWER_DIR }
  $candidates += (Join-Path $PSScriptRoot 'viewer')                    # installed layout
  $candidates += (Join-Path $PSScriptRoot '..\..\viewer')              # source tree
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath (Join-Path $c 'viewer.html')) {
      return (Resolve-Path -LiteralPath $c).ProviderPath
    }
  }
  throw 'Viewer files not found. Run install-windows.ps1.'
}

function Invoke-Main {
  if ($ListBrowsers) { Show-BrowserList; return }
  if ($CheckGiven) { Show-BrowserCheck $CheckBrowser; return }
  $viewerDir = Find-ViewerDir

  $pick = Select-Browser
  if (-not $pick.Path) { throw $pick.From }
  $browser = $pick.Path

  $family = Get-BrowserFamily $browser
  $profileDir = Join-Path $AppData 'firefox-profile'
  if ($family -eq 'firefox' -and -not $DryRun) { Initialize-FirefoxProfile $profileDir }

  $images = @($Path | Where-Object { $_ })
  if ($images.Count -eq 0) { $images = @('') }

  foreach ($img in $images) {
    $full = ''
    if ($img) {
      if ($img -match '^[A-Za-z][A-Za-z0-9+.-]+://') { $full = $img }
      else { $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($img) }
    }
    $url = Get-ViewerUrl $viewerDir $full
    switch ($family) {
      'chromium' { $argList = @("--app=$url") }
      'firefox'  { $argList = @('-profile', $profileDir, '-new-window', $url) }
      default    { $argList = @($url) }
    }
    $argString = ConvertTo-ArgString $argList
    if ($DryRun) {
      Write-Output ((ConvertTo-ArgString @($browser)) + ' ' + $argString)
    } else {
      Start-Process -FilePath $browser -ArgumentList $argString
    }
  }
}

# Dot-sourcing (". .\open-image.ps1") only loads the functions, for tests.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
  Invoke-Main
} catch {
  if ($DryRun -or $ListBrowsers -or $CheckGiven) { throw }
  # Launched hidden from Explorer: show the error instead of failing silently.
  Add-Type -AssemblyName System.Windows.Forms
  [void][System.Windows.Forms.MessageBox]::Show(
    $_.Exception.Message, 'Image Viewer',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Error)
  exit 1
}
