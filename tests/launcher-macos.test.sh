#!/bin/sh
# Tests for launchers/macos/open-image. Runs on Linux or macOS: the macOS tools
# (defaults, mdfind, PlistBuddy, open, osascript) are replaced by stubs and the
# browsers by fake .app bundles, so only the launcher's own logic is tested.

set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib/assert.sh"

SH=$(command -v dash || command -v sh)
T=$(mktemp -d "${TMPDIR:-/tmp}/iv-macos-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/Library/Preferences/com.apple.LaunchServices"
LS_PLIST=$T/home/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist

L="$ROOT/launchers/macos/open-image"
VIEWER_URL="file://$(printf '%s' "$ROOT/viewer/viewer.html" | sed 's/ /%20/g')"
SUPPORT="$T/home/Library/Application Support/ImageViewer"

# Fake apps: <name>.app/Contents/id holds the bundle id; $T/map maps id -> path.
# Browsers also get Contents/urls, printed for "Print :CFBundleURLTypes".
mkapp() {
  mkdir -p "$T/Apps/$1.app/Contents"; echo "$2" > "$T/Apps/$1.app/Contents/id"
  [ "${3:-}" = nourl ] || printf 'Array {\n    Dict {\n        CFBundleURLSchemes = Array {\n            http\n            https\n        }\n    }\n}\n' > "$T/Apps/$1.app/Contents/urls"
  echo "$2 $T/Apps/$1.app" >> "$T/map"
}
mkapp "Google Chrome" com.google.Chrome
mkapp Firefox org.mozilla.firefox
mkapp Safari com.apple.Safari
mkapp Arc company.thebrowser.Browser
mkapp Notes com.apple.Notes nourl

cat > "$T/bin/PlistBuddy" <<'EOF'
#!/bin/sh
case $2 in
  *CFBundleURLTypes*) cat "$(dirname "$3")/urls" 2>/dev/null ;;
  *) cat "$(dirname "$3")/id" ;;
esac
EOF
cat > "$T/bin/mdfind" <<EOF
#!/bin/sh
case \$1 in
  *kMDItemFSName*) n=\$(printf '%s' "\$1" | sed "s/.*kMDItemFSName == '\\(.*\\)'c/\\1/")
                   while read -r i p; do [ "\${p##*/}" = "\$n" ] && echo "\$p"; done < "$T/map"; exit 0 ;;
  *application-bundle*) while read -r i p; do echo "\$p"; done < "$T/map"; exit 0 ;;
  *CFBundleIdentifier*) ;;
  *) exit 0 ;;
esac
id=\$(printf '%s' "\$1" | sed "s/.*== '\\(.*\\)'c/\\1/" | tr 'A-Z' 'a-z')
while read -r i p; do [ "\$(printf %s "\$i" | tr 'A-Z' 'a-z')" = "\$id" ] && echo "\$p"; done < "$T/map"
EOF
printf '#!/bin/sh\ncat "$DEFAULTS_OUT"\n' > "$T/bin/defaults"
chmod +x "$T/bin/"*

# LaunchServices handler list as printed by `defaults read ... LSHandlers`.
set_default() {
  cat > "$T/ls.txt" <<EOF
(
        {
        LSHandlerContentType = "public.html";
        LSHandlerPreferredVersions =         {
            LSHandlerRoleAll = "-";
        };
        LSHandlerRoleAll = "org.mozilla.firefox";
    },
        {
        LSHandlerPreferredVersions =         {
            LSHandlerRoleAll = "-";
        };
        LSHandlerRoleAll = "$1";
        LSHandlerURLScheme = https;
    },
        {
        LSHandlerRoleAll = "com.apple.safari";
        LSHandlerURLScheme = http;
    }
)
EOF
  touch "$LS_PLIST"
}

run() {
  env -i HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" PLISTBUDDY="$T/bin/PlistBuddy" \
    DEFAULTS_OUT="$T/ls.txt" TMPDIR="$T" "$@"
}

set_default com.google.chrome
out=$(run "$SH" "$L" -n "/Users/bob/My Pics/Фото #1.png")
check "default Chrome: open -na ... --app, src is an encoded file URL" "$out" \
  "[open] [-na] [$T/Apps/Google Chrome.app] [--args] [--app=$VIEWER_URL?src=file%3A%2F%2F%2FUsers%2Fbob%2FMy%2520Pics%2F%25D0%25A4%25D0%25BE%25D1%2582%25D0%25BE%2520%25231.png] "

set_default org.mozilla.firefox
out=$(run "$SH" "$L" -n /x/a.png)
check "default Firefox: dedicated profile" "$out" \
  "[open] [-na] [$T/Apps/Firefox.app] [--args] [-profile] [$SUPPORT/firefox-profile] [-new-window] [$VIEWER_URL?src=file%3A%2F%2F%2Fx%2Fa.png] "

set_default com.apple.safari
out=$(run "$SH" "$L" -n /x/a.png)
check_contains "default Safari + Chrome installed -> Chrome" "$out" "[$T/Apps/Google Chrome.app] [--args] [--app="

set_default company.thebrowser.browser
out=$(run "$SH" "$L" -n /x/a.png)
check "unknown browser: open -a with URL" "$out" "[open] [-a] [$T/Apps/Arc.app] [$VIEWER_URL?src=file%3A%2F%2F%2Fx%2Fa.png] "

out=$(run IMAGE_VIEWER_BROWSER="$T/Apps/Safari.app" "$SH" "$L" -n /x/a.png)
check_contains "explicit Safari goes through AppleScript" "$out" "[osascript] [-e] [on run argv]"
check_contains "AppleScript gets the full URL as an argument" "$out" "[$VIEWER_URL?src=file%3A%2F%2F%2Fx%2Fa.png] "

out=$(run IMAGE_VIEWER_BROWSER=org.mozilla.firefox "$SH" "$L" -n)
check "browser by bundle id; no file -> help page" "$out" \
  "[open] [-na] [$T/Apps/Firefox.app] [--args] [-profile] [$SUPPORT/firefox-profile] [-new-window] [$VIEWER_URL] "

out=$(run IMAGE_VIEWER_BROWSER=Nope "$SH" "$L" -n /x/a.png 2>&1); rc=$?
check "unknown configured browser is an error" "$rc:$out" \
  "1:open-image: IMAGE_VIEWER_BROWSER environment variable: browser not found: Nope"

# ---------------------------------------------------- check and list ----
out=$(run "$SH" "$L" --check-browser "Google Chrome" 2>&1); rc=$?
check "--check-browser: app name" "$rc:$out" \
  "0:Google Chrome -> $T/Apps/Google Chrome.app (com.google.Chrome; app window, no tabs)"
out=$(run "$SH" "$L" --check-browser org.mozilla.firefox 2>&1); rc=$?
check "--check-browser: bundle id" "$rc:$out" \
  "0:org.mozilla.firefox -> $T/Apps/Firefox.app (org.mozilla.firefox; own Firefox profile, no tabs)"
out=$(run "$SH" "$L" --check-browser "Gogle Chrome" 2>&1); rc=$?
check "--check-browser: unknown app" "$rc:$out" "1:browser not found: Gogle Chrome"

set_default com.google.chrome
out=$(run "$SH" "$L" --list-browsers 2>&1)
has_line() { printf '%s\n' "$1" | grep -q -E "$2"; }
check_true "--list-browsers: default browser marked" has_line "$out" \
  '^  "Google Chrome" +com\.google\.Chrome +app window, no tabs +system default, in use$'
check_true "--list-browsers: Firefox" has_line "$out" '^  Firefox +org\.mozilla\.firefox +own Firefox profile, no tabs$'
check_true "--list-browsers: Safari" has_line "$out" '^  Safari +com\.apple\.Safari +Safari window, with tabs$'
check_true "--list-browsers: unknown browser still listed" has_line "$out" '^  Arc +company\.thebrowser\.Browser +normal browser window$'
check_true "--list-browsers: apps without http links skipped" sh -c "! printf '%s' \"\$1\" | grep -q Notes" _ "$out"
check_contains "--list-browsers: in use" "$out" "In use now: $T/Apps/Google Chrome.app (system default)"

mkdir -p "$SUPPORT"; echo "IMAGE_VIEWER_BROWSER='org.mozilla.firefox'" > "$SUPPORT/config"
set_default com.google.chrome
out=$(run "$SH" "$L" -n /x/a.png)
check_contains "config file overrides the default" "$out" "[$T/Apps/Firefox.app]"
rm -f "$SUPPORT/config"

rm -f "$LS_PLIST"
printf 'com.apple.Safari %s\n' "$T/Apps/Safari.app" > "$T/map"
out=$(cd "$T" && run "$SH" "$L" -n rel/b.png)
check_contains "no LaunchServices prefs + only Safari -> Safari" "$out" "[osascript]"
check_contains "relative path made absolute" "$out" "src=file%3A%2F%2F$(printf '%s' "$T" | sed 's|/|%2F|g')%2Frel%2Fb.png"

# Real run for a generic browser: writes the window.SRC fallback page.
printf '#!/bin/sh\nexit 0\n' > "$T/bin/open"; chmod +x "$T/bin/open"
run IMAGE_VIEWER_BROWSER="$T/Apps/Arc.app" "$SH" "$L" "/x/a b.png"
page=$(ls "$T"/image-viewer.*.html 2>/dev/null | sed -n 1p)
check_true "fallback page written" test -n "$page"
check_true "fallback page has <base> and window.SRC" grep -q '<base href="file://.*/viewer/"><script>window.SRC="file:///x/a%20b.png";</script>' "$page"

# Real run with Firefox: profile written to Application Support.
echo "org.mozilla.firefox $T/Apps/Firefox.app" >> "$T/map"
run IMAGE_VIEWER_BROWSER=org.mozilla.firefox "$SH" "$L" /x/a.png
check_true "firefox profile written" test -f "$SUPPORT/firefox-profile/chrome/userChrome.css"

finish
