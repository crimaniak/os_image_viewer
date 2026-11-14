@echo off
rem Double-click friendly wrapper for install-windows.ps1 (bypasses the script execution policy for this run).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1" %*
set rc=%errorlevel%
rem Keep the window open when started from Explorer.
echo %cmdcmdline% | find /i "%~nx0" >nul && pause
exit /b %rc%
