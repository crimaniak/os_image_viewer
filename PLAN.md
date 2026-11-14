# Implementation plan — browser-based image viewer

## 1. Architecture

The viewer is plain static files with no build step and no server. It is the same on every OS;
only the launcher and the installer are platform-specific.

```
viewer/
  viewer.html          page: toolbar + image frame
  viewer.css           layout (toolbar on top, frame fills the rest of the viewport)
  viewer.js            state, rendering, input handling
launchers/
  linux/open-image             POSIX sh launcher
  linux/image-viewer.desktop   desktop entry with MimeType list
  macos/ImageViewer.applescript  source of the "Open with" applet
  macos/open-image             POSIX sh launcher (bundled into the applet)
  windows/open-image.ps1       PowerShell launcher
  windows/open-image.cmd       wrapper for terminal use
  windows/ImageViewer.cs       "Open with" stub, compiled at install by the built-in csc.exe
install/
  install-linux.sh   / uninstall-linux.sh
  install-macos.sh   / uninstall-macos.sh
  install-windows.ps1 / uninstall-windows.ps1  (+ .cmd double-click wrappers)
```

**Requirement: no Python anywhere.** Launchers and installers use only what the OS ships:
POSIX `sh` + coreutils/`od`/`awk`/`sed` on Linux and macOS, and PowerShell on Windows.

**How an image gets in:** the OS calls the launcher with the image path. The launcher
builds `file:///<install-dir>/viewer.html?src=<percent-encoded path or file URL>` and starts
the browser with that URL. `viewer.js` reads `src` from `location.search` and turns an
absolute path (`/…` or `C:\…`) into a `file://` URL itself.

- A `file://` page may display a `file://` image in `<img>` (Firefox, Chrome/Edge;
  Safari must be checked). We never draw to a canvas or read pixels, so the
  CORS / "tainted canvas" rules don't apply.
- **The launcher always runs the browser executable directly with the URL as an
  argument.** Handing a `file://…?query` URL to the OS URL handler (`xdg-open`,
  `open`, `start`) can drop the query string, especially on Windows and macOS.
- **Fallback if a browser still drops the query:** the launcher writes a tiny temporary
  HTML file (`<script>window.SRC="…"</script><script src="file:///…/viewer.js">`, which
  shares the same markup) and opens that instead. `viewer.js` accepts either `?src=`
  or `window.SRC`.
- **Path → file URL:** the launcher percent-encodes each path segment (spaces, `#`, `?`,
  `%`, non-ASCII). Windows: `C:\a b\x.jpg` → `file:///C:/a%20b/x.jpg`; UNC
  `\\host\share\x.jpg` → `file://host/share/x.jpg`.
- **Browser selection**, in order: the `IMAGE_VIEWER_BROWSER` env var / config value, then
  the system default browser (if it can be resolved to an executable), then the first
  installed of Chrome, Chromium, Edge, Firefox. A configured browser that can't be found
  is an error. There is no silent fallback.
- **Checking and listing browsers (done):** each launcher has `--list-browsers` and
  `--check-browser VALUE` (`-ListBrowsers` / `-CheckBrowser` on Windows). The installers
  use them for `--list-browsers` and to check `--browser` before changing anything.
  `--browser auto` removes the setting. The sources are:
  - Linux: known command names on `PATH`, plus `.desktop` files that handle `http`.
    Entries are deduplicated by snap name, Flatpak id or real path. Exec lines
    containing `$` or a backtick are skipped, because they are later passed to `eval`.
  - macOS: apps whose `Info.plist` declares the `http` or `https` URL scheme, found via
    Spotlight and the Applications folders.
  - Windows: `HKCU`/`HKLM\SOFTWARE\Clients\StartMenuInternet` (the list Settings uses),
    plus App Paths.
- **Window without tabs or browser UI, where possible:**
  - *Chromium family (Chrome, Chromium, Edge, Brave, Vivaldi):* `--app=<url>` opens a
    separate window with no tabs, address bar or toolbar, and only the title bar.
  - *Firefox:* there is no app mode (`--kiosk` is fullscreen, which isn't wanted). The
    launcher creates a dedicated profile in the app data dir. Its
    `user.js` sets `toolkit.legacyUserProfileCustomizations.stylesheets = true`, and its
    `chrome/userChrome.css` hides `#TabsToolbar`, `#nav-bar`, `#PersonalToolbar` and the
    sidebar. It also turns off the first-run/welcome pages, telemetry prompts and session
    restore, so the window is plain. The launcher writes this profile on every start, so it
    stays correct even if the default browser changes after install. It then runs
    `firefox --profile <dir> --new-window <url>`. Modern Firefox forwards a second call to an
    instance already running with that profile, so `--no-remote` isn't needed.
  - *Safari and others:* a normal new window is the fallback.
  - The window size is left to the browser. Chromium also accepts `--window-size`, if wanted later.

## 2. View model (viewer.js)

State: `scale`, `offsetX`, `offsetY` (image top-left relative to the frame), the
image's `naturalWidth/Height` and the frame size, and `mode` ∈ `fit | actual | free`.

Rendering: the `<img>` is absolutely positioned in the frame and moved with
`transform: translate(offsetX, offsetY) scale(scale)` and `transform-origin: 0 0`.
Every action changes state and calls one `render()` function, batched with
`requestAnimationFrame`.

| Function | Behaviour |
|---|---|
| `zoomAt(factor, cx, cy)` | Multiplies scale by `factor` and keeps the image point under `(cx, cy)` fixed: `offset = c - (c - offset) * factor`. Clamps scale to about 1/50 … 50. Sets `mode = free`. |
| `zoomIn()` / `zoomOut()` | `zoomAt(1.25)` / `zoomAt(0.8)` around the frame center. |
| `zoomAll()` | **Fit to window, upscaling small images too:** `scale = min(fw/iw, fh/ih)`, centered. `mode = fit`. This is the default view on load. |
| `zoom100()` | `scale = 1` (one image pixel per CSS pixel), keeping the image point at the frame center fixed (centered when coming from fit). `mode = actual`. |
| `panBy(dx, dy)` | Shifts the offsets. No limits: the image can be moved anywhere, even out of view. Clears fit mode. Zooming does not re-clamp the position either. |

- **Window resize:** in `fit` mode, fit again; otherwise keep the image point at the frame center.
- **HiDPI (optional):** "100%" means CSS pixels. A setting could use device pixels
  (`scale = 1 / devicePixelRatio`) instead. The default is CSS pixels.
- **SVG without intrinsic size:** if `naturalWidth` is 0, fall back to the viewBox or 1000×1000.

## 3. Input mapping

| Action | Key | Mouse | Toolbar |
|---|---|---|---|
| Zoom in | `+` (also `=`, numpad `+`) | wheel up: zoom at cursor | `+` button |
| Zoom out | `-` (also numpad `-`) | wheel down: zoom at cursor | `−` button |
| Zoom all (fit) | `a` | middle button click | "Fit" button |
| Zoom 100% | `1` (also numpad `1`) | none | "1:1" button |
| Pan | arrow keys (step ~10% of frame, Shift = larger step) | left-drag | none |

Implementation notes:
- **Wheel:** register the `wheel` listener with `{passive: false}` and call `preventDefault()`
  so it doesn't scroll the page or trigger browser zoom on Ctrl+wheel. Normalise
  `deltaMode`/`deltaY` and use a factor like `Math.exp(-deltaY * 0.0015)` so trackpads
  zoom smoothly.
- **Middle button:** call `preventDefault()` on `mousedown` with `button === 1` to stop
  autoscroll, and act on `auxclick`.
- **Drag:** use pointer events (`pointerdown`/`move`/`up` + `setPointerCapture`) so a drag
  keeps working outside the frame. Set `cursor: grab/grabbing`, and put
  `draggable="false"` on the `<img>` to block the native image drag.
- **Keys:** listen for `keydown` on `window` and match on `event.key`. Ignore keys while
  Ctrl/Alt/Meta is held so browser shortcuts still work.
- **Toolbar tooltips:** each button shows its key, e.g. "Fit (A)" and "Actual size (1)".
  The active mode (Fit / 1:1) is highlighted.

## 4. UI (viewer.html / viewer.css)

- **Toolbar:** a fixed-height bar at the top with the buttons Zoom in, Zoom out, Fit and 1:1.
  On the right it shows the file name, the image dimensions and the current zoom %.
- **Frame:** `position: absolute; inset: <toolbar height> 0 0 0; overflow: hidden`, with a
  neutral dark background and a checkerboard behind transparent images.
- **Page title:** `<title>` is the file name.
- **Errors:** with no `src` there is short help text (usage, keys); if `img.onerror` fires
  the page shows "Cannot load <path>".
- **Pixelated zoom:** set `image-rendering: pixelated` when scale > ~3 so zoomed pixels stay
  sharp, and smooth rendering below that.

## 5. Platform integration

Each installer copies `viewer/` into a per-user location, installs the launcher, registers
"Open with" for the image types, and optionally (behind a flag, `--default`) makes the
viewer the default handler. Nothing needs admin rights. Each installer has a matching
uninstaller.

Types: png, jpg/jpeg, gif, webp, svg, bmp, ico, avif. tiff/heic are only listed where the
chosen browser can render them.

### Linux (`install-linux.sh`, done)
- Copies `viewer/` to `~/.local/share/image-viewer/` and `open-image` to `~/.local/bin/`.
- Copies `image-viewer.desktop` (`Exec=open-image %f`,
  `MimeType=image/png;image/jpeg;…`) to `~/.local/share/applications/`, then runs
  `update-desktop-database ~/.local/share/applications`.
- With `--default`, runs `xdg-mime default image-viewer.desktop <type>` for each type.
- **Launcher (done):** POSIX `sh`. It percent-encodes with `od | awk`. It finds the
  browser via `xdg-settings get default-web-browser` and reads `Exec=` from that .desktop
  file; otherwise it takes the first installed from the fallback list. `-n` prints the
  command instead of running it.
- **Sandboxed browsers (done):** snap and Flatpak browsers can't read hidden dirs like
  `~/.local/share`. The launcher detects them, including Ubuntu's `/usr/bin/firefox`
  wrapper around the snap. It copies the viewer (and keeps the Firefox profile) in
  `~/snap/<name>/common/image-viewer/` or `~/.var/app/<id>/data/image-viewer/`. Images in
  hidden dirs or outside `$HOME` may still be blocked by the sandbox.
- **Uninstall (done):** removes the files and the sandbox copies, and removes only our
  entries from `mimeapps.list`. `--purge` also removes the config.

### macOS (`install-macos.sh`, done)
- **App bundle:** Finder passes files to apps through Apple Events, not argv. So the app
  is an AppleScript applet built with `osacompile` from `ImageViewer.applescript`. Its
  `on open` handler passes the quoted POSIX paths to the launcher and shows an alert if
  that fails. `on run` (double-clicking the app) opens the help page. The bundle is
  self-contained: `Contents/Resources/open-image` and `Contents/Resources/viewer/`.
- **Info.plist (via PlistBuddy):** bundle id `local.image-viewer`, the name, `LSUIElement`
  (no Dock icon), and `CFBundleDocumentTypes` with rank `Alternate` for the png, jpeg, gif,
  webp, svg, bmp, ico and avif UTIs. The installer then re-signs ad hoc
  (`codesign --force --deep -s -`) because the bundle was changed, removes the quarantine
  flag, and runs `lsregister -f`. The app goes to `~/Applications/Image Viewer.app`.
- **`--default`:** calls `LSSetDefaultRoleHandlerForContentType` through JavaScript for
  Automation (`osascript -l JavaScript`, built in). It falls back to `duti` if installed,
  and otherwise prints the Get Info → Open with → Change All steps.
- **`--browser APP`:** writes `~/Library/Application Support/ImageViewer/config`. APP can be
  an app name, a bundle id or a `.app` path.
- **Launcher (POSIX sh):** reads the default browser from the LaunchServices prefs
  (`defaults read … LSHandlers`, https then http; with no entry the default is Safari).
  It finds the app via `mdfind` or by scanning the Applications folders, never launching it.
  - **Safari default:** if Chrome, Chromium, Edge, Brave, Vivaldi or Firefox is installed,
    that browser is used instead, because Safari restricts local files.
  - **Commands:** Chromium family `open -na APP --args --app=URL`. Firefox family
    `open -na APP --args -profile DIR -new-window URL`. Safari: AppleScript
    `make new document with properties {URL:…}`, which keeps the query string.
  - **Other browsers:** the launcher writes a copy of `viewer.html` to `$TMPDIR` with
    `<base href>` and `window.SRC` and opens that, because `open -a` may drop
    `?src=` from a file URL.
- **Uninstall:** runs `lsregister -u` and removes the app and the Firefox profile.
  `--purge` also removes the config.

### Windows (`install-windows.ps1`, done)
- **Install:** copies `viewer/`, `open-image.ps1` and `open-image.cmd` to
  `%LOCALAPPDATA%\ImageViewer\` and runs `Unblock-File` on them. `install-windows.cmd`
  and `uninstall-windows.cmd` are double-click wrappers that bypass the execution policy
  for that one run.
- **`ImageViewer.exe` stub:** the installer compiles `launchers/windows/ImageViewer.cs`
  with the `csc.exe` that ships with .NET Framework 4.x on every Windows 10/11. The stub
  runs `open-image.ps1` hidden. It exists so Explorer shows "Image Viewer" rather than
  "Windows PowerShell", and so no console window flashes. If `csc.exe` is missing, the
  installer registers `powershell.exe -WindowStyle Hidden -File …` directly instead.
- **Registry (HKCU only):**
  - ProgID `ImageViewer.Image` with `shell\open\command` and `FriendlyAppName`.
  - `Applications\ImageViewer.exe` with `SupportedTypes`.
  - `.<ext>\OpenWithProgids\ImageViewer.Image` for each extension.
  - `Software\ImageViewer\Capabilities` + `RegisteredApplications`, so the viewer is
    listed in Settings → Default apps.
  - Afterwards it calls `SHChangeNotify` so Explorer picks up the changes.
- **`-Default`:** since Windows 10 the user's choice is hash-protected and a script can't
  set it. The installer opens `ms-settings:defaultapps?registeredAppUser=ImageViewer`
  so the user can confirm it there.
- **`-Browser NAME`:** writes `%APPDATA%\ImageViewer\config.json`.
- **Launcher (PowerShell 5.1/7):** builds `file:///C:/…` and `file://host/share/…` URLs
  with `[Uri]::EscapeDataString` per segment, and handles `\\?\` paths too. Browser:
  `IMAGE_VIEWER_BROWSER` → config → `UrlAssociations\http\UserChoiceLatest`/`UserChoice`
  ProgId → `shell\open\command` → App Paths fallbacks. It quotes arguments per
  CommandLineToArgvW and runs the browser exe directly. If it fails while started from
  Explorer, it shows the error in a message box. `-DryRun` prints the command instead.
  Dot-sourcing the script loads only its functions, for tests.
- **Uninstall:** removes the registry keys, `OpenWithProgids` values and files.
  `-Purge` also removes the config.

## 6. Steps

All steps are implemented. "Verified" means tested on this Linux machine. The Windows
and macOS parts still need a run on the real OS (see `TESTING.md`).

1. **Skeleton (done):** `viewer.html` and CSS layout. Loads the image from `?src=` or
   `window.SRC` and shows the title, help text and errors.
2. **View model (done):** state, `render()`, `zoomAll()` on load (with upscaling),
   `zoom100`, `zoomAt`, free `panBy` (no limits), resize behaviour.
3. **Toolbar (done):** buttons wired to the functions, active-mode highlight, zoom % and
   size display.
4. **Keyboard (done):** `+ - a 1` and the arrow keys.
5. **Mouse (done):** wheel zoom at the cursor, left-drag pan, middle-click fit.
6. **Linux launcher and installer (done, verified):** includes snap Firefox. The file
   manager's Open With entry still needs a manual check.
7. **Windows launcher and installer (done):** logic tested in a PowerShell container and the
   stub compiled with Mono; not yet run on Windows.
8. **macOS applet and installer (done):** launcher logic tested with stubbed macOS tools;
   not yet run on macOS.
9. **Testing (done):** `tests/run-all.sh [--docker]`.
   - `viewer-math.test.js`: unit tests of the view math and path → URL conversion.
   - `viewer-e2e.test.js`: the real page in headless Chrome over the DevTools protocol,
     using only Node built-ins. Fixtures are generated by `tests/lib/png.js`.
   - `launcher-linux.test.sh`, `launcher-macos.test.sh` (stubbed macOS tools) and
     `launcher-windows.test.ps1`. They never start a real browser.
   - Manual checklist in `TESTING.md`, with sample images from `tests/make-samples.js`.
10. **README (done):** features, controls, install/uninstall per OS, browser choice,
    sandbox notes, development and limitations.

## 7. Out of scope

- Next/previous image in the same folder.
