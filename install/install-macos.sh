#!/bin/sh
# Install the image viewer for the current user on macOS (no admin rights, no Python).
#
# Usage: install-macos.sh [--default] [--browser APP] [--list-browsers] [-h]
#
#   --default        make Image Viewer the default app for its image types
#   --browser APP    always use this browser: app name ("Google Chrome"), bundle id
#                    (org.mozilla.firefox) or path to the .app; checked first.
#                    --browser auto removes the setting (use the system default)
#   --list-browsers  show the browsers found on this system and exit
#
# Builds ~/Applications/Image Viewer.app (an AppleScript applet made with osacompile)
# containing the launcher and the viewer, registers it with Launch Services and
# signs it ad hoc so it runs on Apple silicon.

set -eu

SRC=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
APP_DIR=${IMAGE_VIEWER_APP_DIR:-$HOME/Applications}
APP=$APP_DIR/Image\ Viewer.app
SUPPORT=$HOME/Library/Application\ Support/ImageViewer
BUNDLE_ID=local.image-viewer
PB=/usr/libexec/PlistBuddy
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
UTIS="public.png public.jpeg com.compuserve.gif org.webmproject.webp public.svg-image com.microsoft.bmp com.microsoft.ico public.avif"

MAKE_DEFAULT=0
BROWSER=
SET_BROWSER=0
while [ $# -gt 0 ]; do
  case $1 in
    --default) MAKE_DEFAULT=1; shift ;;
    --browser) [ $# -ge 2 ] && [ -n "$2" ] || { echo "--browser needs a value (see --list-browsers)" >&2; exit 2; }
               BROWSER=$2; SET_BROWSER=1; shift 2 ;;
    --list-browsers) exec sh "$SRC/launchers/macos/open-image" --list-browsers ;;
    -h|--help) sed -n '2,14s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = Darwin ] || { echo "This installer is for macOS." >&2; exit 1; }
for f in viewer/viewer.html viewer/viewer.css viewer/viewer.js \
         launchers/macos/open-image launchers/macos/ImageViewer.applescript; do
  [ -f "$SRC/$f" ] || { echo "missing $SRC/$f" >&2; exit 1; }
done

# Check the browser before changing anything.
if [ $SET_BROWSER = 1 ] && [ "$BROWSER" != auto ]; then
  if ! info=$(sh "$SRC/launchers/macos/open-image" --check-browser "$BROWSER" 2>&1); then
    echo "Browser not usable: ${info#open-image: }" >&2
    echo "Run '$0 --list-browsers' to see what is installed." >&2
    exit 1
  fi
fi

pb() { "$PB" -c "$1" "$APP/Contents/Info.plist"; }
pb_set() { pb "Set :$1 $3" 2>/dev/null || pb "Add :$1 $2 $3"; }

# ------------------------------------------------------------ build applet --
echo "Building $APP"
mkdir -p "$APP_DIR"
[ -d "$APP" ] && "$LSREGISTER" -u "$APP" 2>/dev/null || true
rm -rf "$APP"
osacompile -o "$APP" "$SRC/launchers/macos/ImageViewer.applescript"

RES=$APP/Contents/Resources
mkdir -p "$RES/viewer"
cp -f "$SRC/viewer/viewer.html" "$SRC/viewer/viewer.css" "$SRC/viewer/viewer.js" "$RES/viewer/"
cp -f "$SRC/launchers/macos/open-image" "$RES/open-image"
chmod 755 "$RES/open-image"

# ------------------------------------------------------------- Info.plist --
pb_set CFBundleIdentifier string "$BUNDLE_ID"
pb_set CFBundleName string "Image Viewer"
pb_set CFBundleDisplayName string "Image Viewer"
pb_set LSUIElement bool true                      # no Dock icon while the applet runs
pb "Delete :CFBundleDocumentTypes" 2>/dev/null || true
pb "Add :CFBundleDocumentTypes array"
pb "Add :CFBundleDocumentTypes:0 dict"
pb "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Image"
pb "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer"
pb "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate"
pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes array"
i=0
for u in $UTIS; do
  pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:$i string $u"
  i=$((i + 1))
done

# Info.plist and Resources changed after osacompile: re-sign ad hoc, drop quarantine.
if ! codesign --force --deep --sign - "$APP" 2>/dev/null; then
  echo "Warning: ad-hoc signing failed; the app may not open on Apple silicon." >&2
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

"$LSREGISTER" -f "$APP"

# ------------------------------------------------------------------ config --
if [ $SET_BROWSER = 1 ] && [ "$BROWSER" = auto ]; then
  rm -f "$SUPPORT/config"
  echo "Browser setting removed: the system default browser is used."
elif [ $SET_BROWSER = 1 ]; then
  mkdir -p "$SUPPORT"
  esc=$(printf '%s' "$BROWSER" | sed "s/'/'\\\\''/g")
  printf "IMAGE_VIEWER_BROWSER='%s'\n" "$esc" > "$SUPPORT/config"
  echo "Browser set to: $info"
  echo "  (saved in $SUPPORT/config)"
fi

# ----------------------------------------------------------------- default --
if [ $MAKE_DEFAULT = 1 ]; then
  # LSSetDefaultRoleHandlerForContentType via JavaScript for Automation (built in).
  failed=$(osascript -l JavaScript -e '
    function run(argv) {
      ObjC.import("CoreServices");
      var id = $(argv[0]), bad = [];
      for (var i = 1; i < argv.length; i++) {
        var r = $.LSSetDefaultRoleHandlerForContentType($(argv[i]), 0xFFFFFFFF, id);
        if (r !== 0) bad.push(argv[i]);
      }
      return bad.join(" ");
    }' "$BUNDLE_ID" $UTIS 2>/dev/null) || failed="$UTIS"
  if [ -n "$failed" ] && command -v duti >/dev/null 2>&1; then
    still=
    for u in $failed; do duti -s "$BUNDLE_ID" "$u" all 2>/dev/null || still="$still $u"; done
    failed=$still
  fi
  if [ -z "$(printf '%s' "$failed" | tr -d ' ')" ]; then
    echo "Image Viewer is now the default for: $UTIS"
  else
    echo "Could not set the default for:$failed" >&2
    echo "Set it in Finder: select an image > Get Info > Open with > Image Viewer > Change All." >&2
  fi
fi

echo "Done. In Finder: right-click an image > Open With > Image Viewer."
echo "From a terminal: \"$RES/open-image\" FILE"
