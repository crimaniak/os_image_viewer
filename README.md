# Image Viewer

A browser-based image viewer for the file manager. Associate it with image files.
Opening an image starts your browser on a small local page: a toolbar plus an image
area that fills the window. Where the browser allows it, the window has no tabs and
no address bar.

- Plain HTML/CSS/JS. No build step, no server, no Python, nothing to download at run time.
- Linux, Windows and macOS. Per-user install, no admin rights.
- Works with Chrome, Chromium, Edge, Brave, Vivaldi and Firefox. Safari and other
  browsers get a normal window.

## Controls

| Action | Keyboard | Mouse | Toolbar |
|---|---|---|---|
| Zoom in | `+` | wheel up (zooms at the cursor) | magnifier + |
| Zoom out | `-` | wheel down (zooms at the cursor) | magnifier − |
| Zoom all (fit to window, also enlarges small images) | `a` | middle click | **Fit** |
| Zoom 100% | `1` | | **1:1** |
| Pan | arrow keys (Shift = bigger step) | left drag | |

- Panning is unlimited: you can drag the image anywhere. Press `a` to bring it back.
- An image opens fitted to the window.
- Resizing the window re-fits the image, unless you have zoomed or panned.
- Keys pressed with Ctrl, Alt or Cmd are left to the browser.

The toolbar shows the file name, the image size and the current zoom.

## Install

Get the project folder (clone or download), then run the installer for your system
from inside it.

### Linux

```sh
install/install-linux.sh                          # add "Image Viewer" to Open With
install/install-linux.sh --default                # ...and make it the default for images
install/install-linux.sh --browser google-chrome  # always use this browser
install/install-linux.sh --list-browsers          # which --browser values work here
```

The installer puts files here:

| What | Where |
|---|---|
| Viewer | `~/.local/share/image-viewer/viewer/` |
| Launcher | `~/.local/bin/open-image` |
| Desktop entry | `~/.local/share/applications/image-viewer.desktop` |

It needs only a POSIX shell and standard tools (`od`, `awk`, `sed`). Afterwards:
right-click an image → *Open With* → **Image Viewer**. From a terminal:
`open-image photo.jpg`.

**Snap and Flatpak browsers** (Ubuntu's Firefox and Chromium are snaps) can't read hidden
folders such as `~/.local/share`. The launcher detects them and keeps a copy of the
viewer in the browser's own folder: `~/snap/<name>/common/image-viewer/` or
`~/.var/app/<id>/data/image-viewer/`. Images in hidden folders or outside your home
folder may still be blocked by the sandbox.

### Windows 10 / 11

Double-click `install\install-windows.cmd`, or from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1            # Open with entry
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -Default   # + open Default apps
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -Browser chrome
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -ListBrowsers
```

The installer:
- Installs to `%LOCALAPPDATA%\ImageViewer` and registers under `HKCU` only.
- Compiles a tiny `ImageViewer.exe` with the C# compiler built into Windows (.NET Framework 4).
  Thanks to it, *Open with* shows "Image Viewer" and no console window flashes.

Windows doesn't let scripts change the default app. With `-Default`, the installer opens
Settings → Default apps, where you pick Image Viewer. You can also use *Open with →
Choose another app → Always*.

### macOS

```sh
install/install-macos.sh                           # builds ~/Applications/Image Viewer.app
install/install-macos.sh --default                 # ...and make it the default for images
install/install-macos.sh --browser "Google Chrome" # app name, bundle id or .app path
install/install-macos.sh --list-browsers           # which --browser values work here
```

The installer builds a small AppleScript app with `osacompile`, signs it ad hoc and
registers it with Launch Services. Afterwards: right-click an image → *Open With* →
**Image Viewer**. If `--default` can't set the default, use Get Info → *Open with* →
*Change All…*.

Safari restricts local files, so if Safari is your default browser and Chrome, Edge,
Brave, Vivaldi or Firefox is installed, that browser is used instead. Choose Safari
explicitly with `--browser Safari` if you prefer it.

## Choosing the browser

To see which values `--browser` accepts on your system, ask the installer:

| System | Command |
|---|---|
| Linux | `install/install-linux.sh --list-browsers` |
| macOS | `install/install-macos.sh --list-browsers` |
| Windows | `install\install-windows.cmd -ListBrowsers` |

```
Browsers found (use the first column as the --browser value):

  VALUE          WINDOW                        NOTE
  google-chrome  app window, no tabs
  chromium       app window, no tabs           snap
  firefox        own Firefox profile, no tabs  snap, system default, in use

In use now: /snap/bin/firefox (system default)
```

What a value can be:

| System | Value | Examples |
|---|---|---|
| Linux | a command, options allowed | `firefox`, `/opt/brave.com/brave/brave`, `"flatpak run org.chromium.Chromium"`, `"google-chrome --incognito"` |
| macOS | app name, bundle id or `.app` path | `"Google Chrome"`, `org.mozilla.firefox`, `"/Applications/Microsoft Edge.app"` |
| Windows | exe name or full path | `chrome`, `msedge`, `"C:\Program Files\Mozilla Firefox\firefox.exe"` |

- **Checking:** the installer checks the value before installing anything and stops with an
  error if the browser isn't found.
- **Unknown browsers:** a program that isn't a known browser is accepted with a note. It
  gets a normal window.
- **Going back to the default:** `--browser auto` (`-Browser auto` on Windows) removes the
  setting, so the system default browser is used again.
- **From the launcher:** after installing, `open-image --list-browsers` and
  `open-image --check-browser VALUE` do the same. On Windows they are
  `open-image.cmd -ListBrowsers` and `-CheckBrowser VALUE`.

The launcher takes the first match from this list:

1. The `IMAGE_VIEWER_BROWSER` environment variable.
2. The config file written by `--browser` / `-Browser`:

   | System | Config file |
   |---|---|
   | Linux | `~/.config/image-viewer/config` |
   | macOS | `~/Library/Application Support/ImageViewer/config` |
   | Windows | `%APPDATA%\ImageViewer\config.json` |

3. The system default browser.
4. The first installed of Chrome, Chromium, Edge, Brave, Vivaldi and Firefox.

If the browser from 1 or 2 is no longer installed, opening an image shows an error.
On Windows and macOS it appears as a message box or alert. The launcher does not
silently fall back to another browser.

How the window loses its tabs and toolbars depends on the browser:

- **Chromium-based browsers** open in `--app` mode: a plain window with just a title bar.
- **Firefox** has no app mode. The launcher uses a separate profile just for the viewer:
  - Linux: `~/.local/share/image-viewer/firefox-profile`
  - Windows: `%LOCALAPPDATA%\ImageViewer\firefox-profile`
  - macOS: `~/Library/Application Support/ImageViewer/firefox-profile`

  Its `userChrome.css` hides tabs, toolbars and sidebars. Its `user.js` turns off welcome
  pages and session restore. Your normal Firefox profile is not touched. This relies on
  Firefox's `userChrome.css` support, which Mozilla treats as legacy.
- **Other browsers** open a normal window.

To check which command would run, use the launcher's dry-run option:

| System | Command |
|---|---|
| Linux / macOS | `open-image --dry-run photo.jpg` |
| Windows | `open-image.cmd -DryRun photo.jpg` (in `%LOCALAPPDATA%\ImageViewer`) |

## Uninstall

```sh
install/uninstall-linux.sh [--purge]       # --purge also removes the config
install/uninstall-macos.sh [--purge]
install\uninstall-windows.cmd              # or uninstall-windows.ps1 [-Purge]
```

## Opening the viewer directly

`viewer/viewer.html?src=<image>` works in any browser without installing. `src` can be:
- a percent-encoded absolute path (`%2Fhome%2Fme%2Fa.png`, `C%3A%5Cpics%5Ca.png`)
- a `file://` URL
- a relative URL

## Project layout

```
viewer/            viewer.html, viewer.css, viewer.js  (the whole viewer)
launchers/linux/   open-image (sh), image-viewer.desktop
launchers/macos/   open-image (sh), ImageViewer.applescript
launchers/windows/ open-image.ps1, open-image.cmd, ImageViewer.cs
install/           install-/uninstall- scripts per platform
tests/             automated tests and sample generator, see TESTING.md
PLAN.md            design and implementation notes
```

## Development

```sh
tests/run-all.sh             # unit + browser end-to-end + launcher tests
tests/run-all.sh --docker    # also the Windows launcher tests, via a PowerShell container
node tests/make-samples.js   # sample images for the manual checklist
```

See [TESTING.md](TESTING.md) for what each suite covers and the manual checklist.
Node is used only for the tests, not at run time.

## Limitations

- No next/previous image. A local page can't list the files in a folder.
- Formats are whatever the browser can display: PNG, JPEG, GIF, WebP, SVG, BMP, ICO and
  AVIF in current browsers. TIFF, HEIC and RAW generally don't work.
- Sandboxed (snap/Flatpak) browsers can only read images the sandbox allows.
