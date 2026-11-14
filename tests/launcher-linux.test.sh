#!/bin/sh
# Tests for launchers/linux/open-image and the Linux installer.
# Runs under any POSIX sh (uses dash for the launcher when available).
# Everything happens in a throwaway HOME; nothing on the real system changes.

set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/tests/lib/assert.sh"

SH=$(command -v dash || command -v sh)
T=$(mktemp -d "${TMPDIR:-/tmp}/iv-linux-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/bin" "$T/data/applications"

L="$ROOT/launchers/linux/open-image"
VIEWER_URL="file://$(printf '%s' "$ROOT/viewer/viewer.html" | sed 's/ /%20/g')"

# Clean environment: fake HOME, our stub bin first, no xdg-settings unless stubbed.
run() {
  env -i HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" XDG_DATA_HOME="$T/data" \
    XDG_DATA_DIRS="$T/nodata" XDG_CONFIG_HOME="$T/home/.config" "$@"
}

# Stub browsers: the launcher checks that the configured program exists.
for b in google-chrome microsoft-edge epiphany; do
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/$b"; chmod +x "$T/bin/$b"
done
# Stub flatpak: only com.google.Chrome is "installed".
printf '#!/bin/sh\n[ "$1" = info ] || exit 0\n[ "$2" = com.google.Chrome ]\n' > "$T/bin/flatpak"
chmod +x "$T/bin/flatpak"

# ---------------------------------------------------------- encoding/flags --
out=$(run IMAGE_VIEWER_BROWSER=google-chrome "$SH" "$L" -n "/p/Фото #1 a+b 50%.png")
check "chromium family uses --app, path fully encoded" "$out" \
  "google-chrome --app=$VIEWER_URL?src=%2Fp%2F%D0%A4%D0%BE%D1%82%D0%BE%20%231%20a%2Bb%2050%25.png"

out=$(cd "$T" && run IMAGE_VIEWER_BROWSER=google-chrome "$SH" "$L" -n rel.png)
check_contains "relative path made absolute" "$out" "?src=$(printf '%s' "$T" | sed 's|/|%2F|g')%2Frel.png"

out=$(run IMAGE_VIEWER_BROWSER=google-chrome "$SH" "$L" -n "file:///x/a%20b.png")
check_contains "file:// URI passed through (encoded once more as a query value)" "$out" "?src=file%3A%2F%2F%2Fx%2Fa%2520b.png"

out=$(run IMAGE_VIEWER_BROWSER=google-chrome "$SH" "$L" -n)
check "no file opens the help page" "$out" "google-chrome --app=$VIEWER_URL"

out=$(run IMAGE_VIEWER_BROWSER=google-chrome "$SH" "$L" -n /a.png /b.png | wc -l | tr -d ' ')
check "one window per file" "$out" "2"

out=$(run IMAGE_VIEWER_BROWSER=microsoft-edge "$SH" "$L" -n /a.png)
check_contains "edge is chromium family" "$out" "--app="

out=$(run IMAGE_VIEWER_BROWSER=epiphany "$SH" "$L" -n /a.png)
check "unknown browser gets a plain URL" "$out" "epiphany $VIEWER_URL?src=%2Fa.png"

# ------------------------------------------------------------- firefox ----
# Stub firefox so the real one (maybe a snap wrapper) is never used or started.
printf '#!/bin/sh\nexit 0\n' > "$T/bin/firefox"; chmod +x "$T/bin/firefox"
out=$(run IMAGE_VIEWER_BROWSER=firefox "$SH" "$L" -n /a.png)
check "firefox uses the dedicated profile" "$out" \
  "firefox --profile $T/data/image-viewer/firefox-profile --new-window $VIEWER_URL?src=%2Fa.png"

# Real run with a stub firefox: profile files must be written.
run IMAGE_VIEWER_BROWSER=firefox "$SH" "$L" /a.png
check_true "user.js written" test -f "$T/data/image-viewer/firefox-profile/user.js"
check_true "userChrome.css hides tabs" grep -q TabsToolbar "$T/data/image-viewer/firefox-profile/chrome/userChrome.css"
check_true "legacy stylesheets enabled" grep -q 'legacyUserProfileCustomizations.stylesheets", true' "$T/data/image-viewer/firefox-profile/user.js"

# ----------------------------------------------------------- sandboxes ----
# Never reaches the exec line: it is only there for snap detection.
printf '#!/bin/sh\nexit 0\nexec /snap/bin/firefox "$@"\n' > "$T/bin/snap-firefox"; chmod +x "$T/bin/snap-firefox"
out=$(run IMAGE_VIEWER_BROWSER=snap-firefox "$SH" "$L" -n /a.png)
check_contains "snap wrapper detected: viewer copied into ~/snap/<name>/common" "$out" \
  "file://$T/home/snap/firefox/common/image-viewer/viewer/viewer.html"
check_contains "snap firefox profile inside the snap dir" "$out" \
  "--profile $T/home/snap/firefox/common/image-viewer/firefox-profile"

run IMAGE_VIEWER_BROWSER=snap-firefox "$SH" "$L" /a.png
check_true "viewer copied for snap" test -f "$T/home/snap/firefox/common/image-viewer/viewer/viewer.js"

out=$(run IMAGE_VIEWER_BROWSER='flatpak run --branch=stable com.google.Chrome' "$SH" "$L" -n /a.png)
check_contains "flatpak: viewer under ~/.var/app/<id>" "$out" \
  "--app=file://$T/home/.var/app/com.google.Chrome/data/image-viewer/viewer/viewer.html"

# ------------------------------------------------------ default browser ----
printf '#!/bin/sh\necho test-browser.desktop\n' > "$T/bin/xdg-settings"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/chromium-test"
chmod +x "$T/bin/xdg-settings" "$T/bin/chromium-test"
printf '[Desktop Entry]\nName=Test\nExec=chromium-test --flag %%U\n[Desktop Action new]\nExec=wrong\n' \
  > "$T/data/applications/test-browser.desktop"
out=$(run "$SH" "$L" -n /a.png)
check "default browser from xdg-settings + .desktop Exec (field codes stripped)" "$out" \
  "chromium-test --flag --app=$VIEWER_URL?src=%2Fa.png"

mkdir -p "$T/home/.config/image-viewer"
echo "IMAGE_VIEWER_BROWSER='firefox'" > "$T/home/.config/image-viewer/config"
out=$(run "$SH" "$L" -n /a.png)
check_contains "config file overrides the default browser" "$out" "firefox --profile"
out=$(run IMAGE_VIEWER_BROWSER=google-chrome "$SH" "$L" -n /a.png)
check_contains "env var overrides the config file" "$out" "google-chrome --app="
rm -rf "$T/home/.config/image-viewer"

printf '[Desktop Entry]\nExec=not-installed-browser %%u\n' > "$T/data/applications/test-browser.desktop"
out=$(run "$SH" "$L" -n /a.png)
case $out in
  not-installed-browser*) fell_back=no ;;
  *viewer.html*) fell_back=yes ;;
  *) fell_back=no ;;
esac
check "missing default browser falls back to an installed one" "$fell_back" yes

# ---------------------------------------------------- check and list ----
out=$(run "$SH" "$L" --check-browser google-chrome 2>&1); rc=$?
check "--check-browser: known browser" "$rc:$out" "0:google-chrome -> $T/bin/google-chrome (app window, no tabs)"
out=$(run "$SH" "$L" --check-browser googel-chrome 2>&1); rc=$?
check "--check-browser: missing program" "$rc:$out" "1:program not found: googel-chrome"
out=$(run "$SH" "$L" --check-browser "google-chrome 'x" 2>&1); rc=$?
check "--check-browser: bad quoting" "$rc:$out" "1:cannot parse 'google-chrome 'x' (check the quotes)"
out=$(run "$SH" "$L" --check-browser "flatpak run org.example.Nope" 2>&1); rc=$?
check "--check-browser: flatpak app not installed" "$rc:$out" "1:flatpak app not installed: org.example.Nope"
out=$(run "$SH" "$L" --check-browser epiphany 2>&1); rc=$?
check_contains "--check-browser: unknown program is accepted with a note" "$rc:$out" "0:epiphany -> $T/bin/epiphany (normal browser window)"
out=$(run IMAGE_VIEWER_BROWSER=googel-chrome "$SH" "$L" -n /a.png 2>&1); rc=$?
check "configured browser missing at run time is an error" "$rc:$out" \
  "1:open-image: IMAGE_VIEWER_BROWSER environment variable: program not found: googel-chrome"

mkdir -p "$T/data2/applications"
printf '[Desktop Entry]\nName=FP\nExec=flatpak run --branch=stable --command=chrome --file-forwarding com.google.Chrome @@u %%U @@\nMimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;\n' \
  > "$T/data2/applications/com.google.Chrome.desktop"
printf '[Desktop Entry]\nName=Hidden\nExec=hiddenchrome %%U\nNoDisplay=true\nMimeType=x-scheme-handler/http;\n' \
  > "$T/data2/applications/hidden.desktop"
printf '[Desktop Entry]\nName=Editor\nExec=epiphany %%F\nMimeType=text/plain;\n' > "$T/data2/applications/editor.desktop"
printf '[Desktop Entry]\nName=Daemon\nExec=/usr/bin/false\nMimeType=x-scheme-handler/http;\n' > "$T/data2/applications/daemon.desktop"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/hiddenchrome"; chmod +x "$T/bin/hiddenchrome"
printf "[Desktop Entry]\nName=Chrome\nExec=$T/bin/google-chrome %%U\nMimeType=x-scheme-handler/https;\n" > "$T/data2/applications/chrome.desktop"
printf '[Desktop Entry]\nName=Evil\nExec=google-chrome $(touch %s/evil)\nMimeType=x-scheme-handler/http;\n' "$T" > "$T/data2/applications/evil.desktop"
ln -s "$T/missing.desktop" "$T/data2/applications/dangling.desktop"
out=$(run IMAGE_VIEWER_BROWSER=google-chrome XDG_DATA_DIRS="$T/data2" "$SH" "$L" --list-browsers 2>&1)
check_true "--list-browsers: browser on PATH, marked in use" \
  sh -c "printf '%s\n' \"\$1\" | grep -q -E '^  google-chrome +app window, no tabs +in use$'" _ "$out"
check_true "--list-browsers: flatpak from its .desktop, shortened" \
  sh -c "printf '%s\n' \"\$1\" | grep -q -E '^  \"flatpak run com.google.Chrome\" +app window, no tabs +flatpak$'" _ "$out"
check_contains "--list-browsers: names the browser in use" "$out" "In use now: google-chrome (IMAGE_VIEWER_BROWSER environment variable)"
check_true "--list-browsers: skips NoDisplay, non-browser and placeholder entries" \
  sh -c "! printf '%s' \"\$1\" | grep -q -e hiddenchrome -e epiphany -e /usr/bin/false" _ "$out"
check "--list-browsers: same browser from PATH and .desktop listed once" \
  "$(printf '%s\n' "$out" | grep -c -E '^  (google-chrome|\S*\/bin\/google-chrome) ')" 1
check_true "--list-browsers: never runs code from Exec lines" test ! -e "$T/evil"
check_true "--list-browsers: no awk errors" sh -c "! printf '%s' \"\$1\" | grep -q -i -e awk -e 'No such file'" _ "$out"

# -------------------------------------------------------- install cycle ----
H2=$T/home2; mkdir -p "$H2/.config"
printf '[Default Applications]\nimage/png=other.desktop;\ntext/plain=kate.desktop;\n' > "$H2/.config/mimeapps.list"
inst() { env HOME="$H2" XDG_DATA_HOME= XDG_CONFIG_HOME= PATH="$T/bin:/usr/bin:/bin" "$@" >/dev/null 2>&1; }
inst "$SH" "$ROOT/install/install-linux.sh" --browser googel-chrome; rc=$?
check "installer rejects a missing browser" "$rc" 1
check_true "...and installs nothing" test ! -e "$H2/.local"
inst "$SH" "$ROOT/install/install-linux.sh" --browser "google-chrome --incognito"
check_true "installed viewer" test -f "$H2/.local/share/image-viewer/viewer/viewer.html"
check_true "installed launcher is executable" test -x "$H2/.local/bin/open-image"
check_true "desktop file installed" grep -q "^Exec=\"$H2/.local/bin/open-image\" %F$" "$H2/.local/share/applications/image-viewer.desktop"
if command -v desktop-file-validate >/dev/null 2>&1; then
  check_true "desktop file is valid" desktop-file-validate "$H2/.local/share/applications/image-viewer.desktop"
fi
check "config written" "$(cat "$H2/.config/image-viewer/config")" "IMAGE_VIEWER_BROWSER='google-chrome --incognito'"
out=$(env HOME="$H2" PATH="$T/bin:/usr/bin:/bin" "$SH" "$H2/.local/bin/open-image" -n /a.png)
check_contains "installed launcher uses installed viewer and config" "$out" \
  "google-chrome --incognito --app=file://$H2/.local/share/image-viewer/viewer/viewer.html"

if command -v xdg-mime >/dev/null 2>&1; then
  inst "$SH" "$ROOT/install/install-linux.sh" --default
  check_true "--default sets image/png" grep -q '^image/png=image-viewer.desktop' "$H2/.config/mimeapps.list"
fi

inst "$SH" "$ROOT/install/install-linux.sh" --browser auto
check_true "--browser auto removes the config" test ! -e "$H2/.config/image-viewer/config"

inst "$SH" "$ROOT/install/uninstall-linux.sh" --purge
check_true "uninstall removed launcher" test ! -e "$H2/.local/bin/open-image"
check_true "uninstall removed data" test ! -e "$H2/.local/share/image-viewer"
check_true "uninstall removed desktop file" test ! -e "$H2/.local/share/applications/image-viewer.desktop"
check_true "uninstall --purge removed config" test ! -e "$H2/.config/image-viewer"
check_true "mimeapps: our entries gone" sh -c "! grep -q image-viewer '$H2/.config/mimeapps.list'"
check_true "mimeapps: other entries kept" grep -q '^text/plain=kate.desktop;' "$H2/.config/mimeapps.list"

finish
