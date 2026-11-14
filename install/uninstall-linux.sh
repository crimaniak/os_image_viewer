#!/bin/sh
# Remove the image viewer installed by install-linux.sh.
#
# Usage: uninstall-linux.sh [--purge]
#
#   --purge   also remove the config file (~/.config/image-viewer)

set -eu

DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
APP_DIR=$DATA_HOME/image-viewer
BIN_DIR=${IMAGE_VIEWER_BIN_DIR:-$HOME/.local/bin}
APPS_DIR=$DATA_HOME/applications
DESKTOP_ID=image-viewer.desktop
PURGE=0

case ${1:-} in
  --purge) PURGE=1 ;;
  -h|--help) sed -n '2,6s/^# \{0,1\}//p' "$0"; exit 0 ;;
  '') ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

rm_verbose() { if [ -e "$1" ]; then echo "Removing $1"; rm -rf -- "$1"; fi; }

# Only remove the launcher if it is ours.
if [ -f "$BIN_DIR/open-image" ] && grep -q 'image-viewer launcher' "$BIN_DIR/open-image"; then
  rm_verbose "$BIN_DIR/open-image"
fi
rm_verbose "$APPS_DIR/$DESKTOP_ID"
rm_verbose "$APP_DIR"                                   # viewer + Firefox profile

# Copies made for sandboxed browsers.
for d in "$HOME"/snap/*/common/image-viewer "$HOME"/.var/app/*/data/image-viewer; do
  [ -d "$d" ] && rm_verbose "$d"
done

[ $PURGE = 1 ] && rm_verbose "$CONFIG_HOME/image-viewer"

# Drop default-app associations pointing at us.
for list in "$CONFIG_HOME/mimeapps.list" "$DATA_HOME/applications/mimeapps.list"; do
  [ -f "$list" ] && grep -q "$DESKTOP_ID" "$list" || continue
  echo "Cleaning $list"
  tmp=$list.tmp.$$
  if sed -e 's/image-viewer\.desktop;\{0,1\}//g' -e '/^[A-Za-z0-9.+_/-]*=$/d' "$list" > "$tmp"; then
    mv -f "$tmp" "$list"
  else
    rm -f "$tmp"
  fi
done

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
for k in kbuildsycoca6 kbuildsycoca5; do
  if command -v $k >/dev/null 2>&1; then $k >/dev/null 2>&1 || true; break; fi
done

echo "Done."
