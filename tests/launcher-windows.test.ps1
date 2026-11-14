# Tests for launchers/windows/open-image.ps1 (pure functions; plus a full
# dry run when actually on Windows). Runs with Windows PowerShell 5.1 or
# PowerShell 7 on any OS:  pwsh -NoProfile -File tests/launcher-windows.test.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$script:Pass = 0
$script:Fail = 0

function Check([string]$Name, $Got, $Want) {
  if ($Got -ceq $Want) { $script:Pass++; Write-Output "ok   $Name" }
  else { $script:Fail++; Write-Output "FAIL $Name`n  got:  $Got`n  want: $Want" }
}

# Parse every Windows script.
foreach ($f in @("$Root/launchers/windows/open-image.ps1", "$Root/install/install-windows.ps1",
                 "$Root/install/uninstall-windows.ps1")) {
  $tokens = $null; $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
  Check "parses: $(Split-Path -Leaf $f)" ($errors.Count) 0
}

# Windows PowerShell 5.1 reads BOM-less files as ANSI: keep the scripts ASCII.
foreach ($f in Get-ChildItem "$Root/launchers/windows", "$Root/install" -File |
               Where-Object { $_.Extension -in '.ps1', '.cmd', '.cs' }) {
  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  Check "ASCII only: $($f.Name)" (@($bytes | Where-Object { $_ -gt 127 }).Count) 0
}

if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [IO.Path]::GetTempPath() }
if (-not $env:APPDATA) { $env:APPDATA = [IO.Path]::GetTempPath() }
. "$Root/launchers/windows/open-image.ps1"     # dot-source: functions only

Check 'drive path'     (ConvertTo-FileUrl ('C:\My Pics\' + [char]0x0424 + ' #1 a+b%.png')) 'file:///C:/My%20Pics/%D0%A4%20%231%20a%2Bb%25.png'
Check 'UNC path'       (ConvertTo-FileUrl '\\nas\share\x y.jpg') 'file://nas/share/x%20y.jpg'
Check 'long path'      (ConvertTo-FileUrl '\\?\C:\a\b.png') 'file:///C:/a/b.png'
Check 'long UNC path'  (ConvertTo-FileUrl '\\?\UNC\nas\s\b.png') 'file://nas/s/b.png'
Check 'URL passthru'   (ConvertTo-FileUrl 'file:///C:/a.png') 'file:///C:/a.png'
Check 'viewer URL'     (Get-ViewerUrl 'C:\Users\Bob Smith\AppData\Local\ImageViewer\viewer' 'C:\p\a b.png') 'file:///C:/Users/Bob%20Smith/AppData/Local/ImageViewer/viewer/viewer.html?src=file%3A%2F%2F%2FC%3A%2Fp%2Fa%2520b.png'
Check 'viewer URL, no image' (Get-ViewerUrl 'C:\v\' '') 'file:///C:/v/viewer.html'
Check 'arg quoting'    (ConvertTo-ArgString @('-profile', 'C:\Users\Bob Smith\p', '--app=file:///x?src=y', 'a"b', 'end\ ', 'C:\a b\', '')) '-profile "C:\Users\Bob Smith\p" --app=file:///x?src=y "a\"b" "end\ " "C:\a b\\" ""'
Check 'exe from quoted command'   (Get-CommandExe '"C:\Program Files\Mozilla Firefox\firefox.exe" -osint -url "%1"') 'C:\Program Files\Mozilla Firefox\firefox.exe'
Check 'exe from unquoted command' (Get-CommandExe 'C:\Program Files\Foo\foo.exe --single-argument %1') 'C:\Program Files\Foo\foo.exe'
Check 'family: Edge'    (Get-BrowserFamily 'C:\x\msedge.exe') 'chromium'
Check 'family: Chrome'  (Get-BrowserFamily 'chrome.exe') 'chromium'
Check 'family: Brave'   (Get-BrowserFamily 'brave.exe') 'chromium'
Check 'family: Firefox' (Get-BrowserFamily 'C:\x\firefox.exe') 'firefox'
Check 'family: other'   (Get-BrowserFamily 'C:\x\iexplore.exe') 'generic'

$prof = Join-Path ([IO.Path]::GetTempPath()) ("iv-ffp-" + [guid]::NewGuid())
Initialize-FirefoxProfile $prof
Check 'firefox user.js'        (Test-Path (Join-Path $prof 'user.js')) $true
Check 'firefox userChrome.css' ((Get-Content -Raw (Join-Path $prof 'chrome/userChrome.css')) -match 'TabsToolbar') $true
Remove-Item -Recurse -Force $prof

# ------------------------------------------------- checking and listing ----
$L = "$Root/launchers/windows/open-image.ps1"
$pos = (Get-Command $L).Parameters['CheckBrowser'].ParameterSets.Values | ForEach-Object { $_.Position }
Check 'bare arguments never bind to -CheckBrowser' (@($pos | Where-Object { $_ -ge 0 }).Count) 0

$fake = Join-Path ([IO.Path]::GetTempPath()) ("iv-list-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $fake 'Google Chrome') | Out-Null
$chromeExe = Join-Path $fake 'Google Chrome/chrome.exe'
$foxExe = Join-Path $fake 'firefox.exe'
$oddExe = Join-Path $fake 'odd.exe'
foreach ($e in $chromeExe, $foxExe, $oddExe) { Set-Content -LiteralPath $e -Value '' }

Check 'Test-Browser: full path' (Test-Browser $chromeExe) $chromeExe
$msg = try { Test-Browser 'googel-chrome'; 'no error' } catch { $_.Exception.Message }
Check 'Test-Browser: unknown name' $msg 'Browser not found: googel-chrome'
$msg = try { Test-Browser 'C:\nope\chrome.exe'; 'no error' } catch { $_.Exception.Message }
Check 'Test-Browser: missing path' $msg 'Browser not found: C:\nope\chrome.exe'
$msg = try { Test-Browser ' '; 'no error' } catch { $_.Exception.Message }
Check 'Test-Browser: empty' $msg 'Empty browser value.'
Check 'window mode: chrome'  (Get-WindowMode $chromeExe) 'app window, no tabs'
Check 'window mode: firefox' (Get-WindowMode $foxExe) 'own Firefox profile, no tabs'
Check 'window mode: other'   (Get-WindowMode $oddExe) 'normal browser window'

$out = @(& $L -CheckBrowser $chromeExe)
Check 'launcher -CheckBrowser: ok' $out[0] "$chromeExe -> $chromeExe (app window, no tabs)"
$out = @(& $L -CheckBrowser $oddExe)
Check 'launcher -CheckBrowser: unknown browser gets a note' ($out[1] -like 'note: not a known browser*') $true
$msg = try { & $L -CheckBrowser 'googel-chrome'; 'no error' } catch { $_.Exception.Message }
Check 'launcher -CheckBrowser: error is thrown, not a message box' $msg 'Browser not found: googel-chrome'

$reg = @([pscustomobject]@{ Name = 'Google Chrome'; Path = $chromeExe },
         [pscustomobject]@{ Name = 'Mozilla Firefox'; Path = $foxExe },
         [pscustomobject]@{ Name = 'Again'; Path = $foxExe.ToUpperInvariant() })
$rows = @(Get-BrowserList $reg $foxExe $chromeExe)
Check 'browser list: duplicates merged' $rows.Count 2
Check 'browser list: not on PATH -> full path as value' $rows[0].Value $chromeExe
Check 'browser list: registered name' $rows[0].Name 'Google Chrome'
Check 'browser list: in use' $rows[0].Note 'in use'
Check 'browser list: system default' $rows[1].Note 'system default'
$table = @(Format-BrowserTable $rows)
Check 'table: header' ($table[0] -match '^  VALUE +NAME +WINDOW +NOTE$') $true
Check 'table: value with spaces is quoted' ($table[1].StartsWith('  "' + $chromeExe + '"  ')) $true
Check 'table: columns line up' ($table[1].LastIndexOf('Google Chrome') -eq $table[0].IndexOf('NAME')) $true
Check 'table: empty' (Format-BrowserTable @()) '  (none found)'

$env:IMAGE_VIEWER_BROWSER = $foxExe
$pick = Select-Browser
Check 'Select-Browser: env var' "$($pick.Path)|$($pick.From)" "$foxExe|IMAGE_VIEWER_BROWSER environment variable"
$env:IMAGE_VIEWER_BROWSER = 'googel-chrome'
$pick = Select-Browser
Check 'Select-Browser: missing configured browser' "$($pick.Path)|$($pick.From)" '|IMAGE_VIEWER_BROWSER environment variable: browser not found: googel-chrome'
$out = (& $L -ListBrowsers) -join "`n"
Check 'launcher -ListBrowsers: reports the problem' ($out -like '*In use now: none (IMAGE_VIEWER_BROWSER environment variable: browser not found: googel-chrome)*') $true
$env:IMAGE_VIEWER_BROWSER = $null
Remove-Item -Recurse -Force $fake

# Full dry run of the launcher (needs real Windows paths).
if ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
  $fake = Join-Path ([IO.Path]::GetTempPath()) ("iv-browser-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $fake | Out-Null
  $chrome = Join-Path $fake 'chrome.exe'
  Set-Content -LiteralPath $chrome -Value ''
  $env:IMAGE_VIEWER_BROWSER = $chrome
  $out = & "$Root/launchers/windows/open-image.ps1" -DryRun 'C:\Pics\a b.png'
  Check 'dry run: --app with encoded src' ($out -like "*chrome.exe* --app=file:///*/viewer/viewer.html?src=file%3A%2F%2F%2FC%3A%2FPics%2Fa%2520b.png") $true
  $env:IMAGE_VIEWER_BROWSER = $null
  Remove-Item -Recurse -Force $fake
} else {
  Write-Output 'skip full dry run (not on Windows)'
}

Write-Output "launcher-windows.test.ps1: $($script:Pass) passed, $($script:Fail) failed"
if ($script:Fail -gt 0) { exit 1 }
