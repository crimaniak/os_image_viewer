#!/bin/sh
# Run all automated tests.
#
# Usage: tests/run-all.sh [--docker]
#
#   --docker   run the PowerShell tests in the mcr.microsoft.com/powershell
#              container when pwsh is not installed locally
#
# Needs: node (>= 22) for the viewer tests; Chrome/Chromium/Edge for the
# end-to-end test (skipped otherwise; set CHROME_BIN to choose one).

set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$ROOT" || exit 1
DOCKER=0
[ "${1:-}" = --docker ] && DOCKER=1

failed=
step() { printf '\n=== %s\n' "$1"; }

step 'viewer: unit + end-to-end (node --test)'
if command -v node >/dev/null 2>&1; then
  node --test tests/*.test.js || failed="$failed node"
else
  echo 'skip: node not found'
fi

step 'Linux launcher + installer'
sh tests/launcher-linux.test.sh || failed="$failed linux"

step 'macOS launcher (stubbed macOS tools)'
sh tests/launcher-macos.test.sh || failed="$failed macos"

step 'Windows launcher (PowerShell)'
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -File tests/launcher-windows.test.ps1 || failed="$failed windows"
elif [ $DOCKER = 1 ] && command -v docker >/dev/null 2>&1; then
  docker run --rm -v "$ROOT":/src:ro mcr.microsoft.com/powershell:latest \
    pwsh -NoProfile -File /src/tests/launcher-windows.test.ps1 || failed="$failed windows"
else
  echo 'skip: pwsh not found (install PowerShell or use --docker)'
fi

echo
if [ -n "$failed" ]; then
  echo "FAILED:$failed"
  exit 1
fi
echo 'All test suites passed.'
