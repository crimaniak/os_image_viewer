#!/bin/sh
# Remove the image viewer installed by install-macos.sh.
#
# Usage: uninstall-macos.sh [--purge]
#
#   --purge   also remove the config file

set -eu

APP_DIR=${IMAGE_VIEWER_APP_DIR:-$HOME/Applications}
APP=$APP_DIR/Image\ Viewer.app
SUPPORT=$HOME/Library/Application\ Support/ImageViewer
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
PURGE=0

case ${1:-} in
  --purge) PURGE=1 ;;
  -h|--help) sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 0 ;;
  '') ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

if [ -d "$APP" ]; then
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
  echo "Removing $APP"
  rm -rf "$APP"
fi

if [ -d "$SUPPORT" ]; then
  if [ $PURGE = 1 ]; then
    echo "Removing $SUPPORT"
    rm -rf "$SUPPORT"
  else
    echo "Removing $SUPPORT/firefox-profile (keeping config)"
    rm -rf "$SUPPORT/firefox-profile"
    rmdir "$SUPPORT" 2>/dev/null || true
  fi
fi

echo "Done. Image types that used Image Viewer by default are handled by another app again (usually Preview)."
