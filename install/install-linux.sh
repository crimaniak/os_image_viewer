#!/bin/sh
# Install the image viewer for the current user (no root, no Python).
#
# Usage: install-linux.sh [--default] [--browser COMMAND] [--list-browsers] [-h]
#
#   --default          make Image Viewer the default app for its image types
#   --browser COMMAND  always use this browser (checked, then written to the config
#                      file), e.g. --browser google-chrome  or  --browser firefox;
#                      --browser auto removes the setting (use the system default)
#   --list-browsers    show the browsers found on this system and exit
#
# Installs:
#   ~/.local/share/image-viewer/viewer/     viewer.html, viewer.css, viewer.js
#   ~/.local/bin/open-image                 launcher
#   ~/.local/share/applications/image-viewer.desktop

set -eu

SRC=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
APP_DIR=$DATA_HOME/image-viewer
BIN_DIR=${IMAGE_VIEWER_BIN_DIR:-$HOME/.local/bin}
APPS_DIR=$DATA_HOME/applications
DESKTOP_ID=image-viewer.desktop

MAKE_DEFAULT=0
BROWSER=
SET_BROWSER=0

while [ $# -gt 0 ]; do
  case $1 in
    --default) MAKE_DEFAULT=1; shift ;;
    --browser) [ $# -ge 2 ] && [ -n "$2" ] || { echo "--browser needs a value (see --list-browsers)" >&2; exit 2; }
               BROWSER=$2; SET_BROWSER=1; shift 2 ;;
    --list-browsers) exec sh "$SRC/launchers/linux/open-image" --list-browsers ;;
    -h|--help) sed -n '2,15s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

for f in viewer/viewer.html viewer/viewer.css viewer/viewer.js \
         launchers/linux/open-image launchers/linux/image-viewer.desktop; do
  [ -f "$SRC/$f" ] || { echo "missing $SRC/$f" >&2; exit 1; }
done

# Check the browser before changing anything.
if [ $SET_BROWSER = 1 ] && [ "$BROWSER" != auto ]; then
  if ! info=$(sh "$SRC/launchers/linux/open-image" --check-browser "$BROWSER" 2>&1); then
    echo "Browser not usable: ${info#open-image: }" >&2
    echo "Run '$0 --list-browsers' to see what is installed." >&2
    exit 1
  fi
fi

# Escape a string for use as a sed replacement with '|' as delimiter.
sed_repl() { printf '%s' "$1" | sed 's/[\\|&]/\\&/g'; }

echo "Installing viewer to $APP_DIR/viewer"
mkdir -p "$APP_DIR/viewer"
cp -f "$SRC/viewer/viewer.html" "$SRC/viewer/viewer.css" "$SRC/viewer/viewer.js" "$APP_DIR/viewer/"

echo "Installing launcher to $BIN_DIR/open-image"
mkdir -p "$BIN_DIR"
cp -f "$SRC/launchers/linux/open-image" "$BIN_DIR/open-image"
chmod 755 "$BIN_DIR/open-image"

echo "Installing $APPS_DIR/$DESKTOP_ID"
mkdir -p "$APPS_DIR"
LAUNCHER=$BIN_DIR/open-image
# Exec= value: quote and escape per the Desktop Entry spec.
EXEC_QUOTED=\"$(printf '%s' "$LAUNCHER" | sed 's/[\\"`$]/\\\\&/g')\"
sed -e "s|@LAUNCHER@|$(sed_repl "$EXEC_QUOTED")|" \
    -e "s|@LAUNCHER_TRYEXEC@|$(sed_repl "$LAUNCHER")|" \
    "$SRC/launchers/linux/image-viewer.desktop" > "$APPS_DIR/$DESKTOP_ID"
chmod 644 "$APPS_DIR/$DESKTOP_ID"

if [ $SET_BROWSER = 1 ] && [ "$BROWSER" = auto ]; then
  rm -f "$CONFIG_HOME/image-viewer/config"
  rmdir "$CONFIG_HOME/image-viewer" 2>/dev/null || true
  echo "Browser setting removed: the system default browser is used."
elif [ $SET_BROWSER = 1 ]; then
  mkdir -p "$CONFIG_HOME/image-viewer"
  esc=$(printf '%s' "$BROWSER" | sed "s/'/'\\\\''/g")
  printf "IMAGE_VIEWER_BROWSER='%s'\n" "$esc" > "$CONFIG_HOME/image-viewer/config"
  echo "Browser set to: $info"
  echo "  (saved in $CONFIG_HOME/image-viewer/config)"
fi

# Refresh desktop/MIME caches (best effort).
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
for k in kbuildsycoca6 kbuildsycoca5; do
  if command -v $k >/dev/null 2>&1; then $k >/dev/null 2>&1 || true; break; fi
done

if [ $MAKE_DEFAULT = 1 ]; then
  if command -v xdg-mime >/dev/null 2>&1; then
    types=$(sed -n 's/^MimeType=//p' "$APPS_DIR/$DESKTOP_ID" | tr ';' ' ')
    failed=
    for t in $types; do
      xdg-mime default "$DESKTOP_ID" "$t" >/dev/null 2>&1 || failed="$failed $t"
    done
    echo "Image Viewer is now the default for: $types"
    [ -z "$failed" ] || echo "Warning: xdg-mime failed for:$failed" >&2
  else
    echo "xdg-mime not found; set the default via your file manager (Open With)." >&2
  fi
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Note: $BIN_DIR is not in PATH; the file manager still works, but to run"
     echo "      'open-image' from a terminal add it to PATH." ;;
esac

echo "Done. Right-click an image -> Open With -> Image Viewer."
