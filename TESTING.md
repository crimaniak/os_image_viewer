# Testing

## Automated

```sh
tests/run-all.sh            # everything that can run on this machine
tests/run-all.sh --docker   # + Windows launcher tests in a PowerShell container
```

| Suite | File | Needs | What it covers |
|---|---|---|---|
| Viewer math | `tests/viewer-math.test.js` | Node ≥ 22 | fit / 100% / zoom-at-point / free pan / resize / wheel / path → URL |
| Viewer end-to-end | `tests/viewer-e2e.test.js` | Node ≥ 22 + Chrome, Chromium or Edge (`CHROME_BIN`) | the real page in headless Chrome: keys, wheel, drag, middle click, toolbar, resize, odd file names, SVG, error and help pages, `window.SRC` fallback page |
| Linux launcher | `tests/launcher-linux.test.sh` | POSIX sh | browser families, encoding, Firefox profile, snap/Flatpak copies, default-browser lookup, config precedence, `--check-browser` / `--list-browsers` (.desktop scan, dedupe, no code run from Exec lines), installer rejecting a missing browser, `--browser auto`, install → uninstall cycle in a throwaway HOME |
| macOS launcher | `tests/launcher-macos.test.sh` | POSIX sh (runs on Linux too) | same, with `defaults`/`mdfind`/`PlistBuddy`/`open` stubbed and fake `.app` bundles; `--check-browser` / `--list-browsers` |
| Windows launcher | `tests/launcher-windows.test.ps1` | PowerShell 5.1 or 7 (or Docker) | script parsing, ASCII-only check, file URLs (drive, UNC, `\\?\`), argument quoting, browser detection, Firefox profile, `-CheckBrowser` / `-ListBrowsers` (merging, table, errors thrown instead of a message box), bare arguments never binding to `-CheckBrowser`; full dry run on Windows |

The launcher tests never start a real browser; they use `--dry-run` or stub executables.
Node is only needed for tests, not for using the viewer.

Not covered automatically (needs the real OS): `osacompile`/codesign/Launch Services on
macOS, `csc.exe` and the registry on Windows, file-manager integration on Linux, and
whether Firefox actually hides its tabs with the generated `userChrome.css`.

## Manual checklist

Generate sample images first:

```sh
node tests/make-samples.js        # -> tests/out/samples/
```

### Viewer (every browser you support)

- [ ] `tiny-64x32.png` opens **fitted and upscaled**, centered; *Fit* is highlighted.
- [ ] `huge-6000x4000.png` opens fitted; zoom % shown is below 100%.
- [ ] `wide-4000x100.png` / `tall-100x4000.png` fit along the long side, centered.
- [ ] `1` / *1:1* → 100%, image stays centered; *1:1* highlighted.
- [ ] `+` / `-` and toolbar buttons zoom around the window center.
- [ ] Mouse wheel zooms **at the cursor** (the pixel under the cursor stays put); trackpad pinch/scroll is smooth.
- [ ] `a` / middle click / *Fit* return to fit; middle click does **not** start autoscroll.
- [ ] Left drag pans freely, even completely out of view; cursor shows grab / grabbing.
- [ ] Arrow keys pan (→ shows more of the right side); Shift+arrow moves 4× further.
- [ ] Ctrl/Cmd + `+`/`-` still do the browser's own zoom (not hijacked).
- [ ] Resize the window: in fit mode the image re-fits; after zoom/pan the center point stays.
- [ ] `pixel-art-16x16.png` at high zoom shows sharp square pixels.
- [ ] `transparent-circle.png` shows a checkerboard behind transparent areas.
- [ ] `sized.svg` and `no-intrinsic-size.svg` display; dimensions shown (or "no intrinsic size").
- [ ] An animated GIF animates.
- [ ] `name with spaces #1 50% + плюс.png` opens; title and toolbar show the exact name.
- [ ] A missing / unreadable file shows "Cannot load image"; opening without a file shows the help.
- [ ] Light and dark system theme both look right.

### Linux

- [ ] `install/install-linux.sh`: "Image Viewer" appears in the file manager's *Open With* (Dolphin, Nautilus, Thunar…).
- [ ] Opening an image from the file manager works with: default browser, Chrome (`--app` window without tabs), Firefox (dedicated profile, no tabs/toolbar).
- [ ] Snap Firefox / Chromium: image in `~/Pictures` opens; image in a hidden dir is expected to fail (sandbox).
- [ ] Selecting several images → one window each.
- [ ] `--default`: double-click opens in Image Viewer. `uninstall-linux.sh` removes it and the association.
- [ ] `install-linux.sh --list-browsers` lists your browsers (native, snap, Flatpak) with the default marked; `--browser nonsense` stops before installing.

### Windows 10 / 11

- [ ] `install\install-windows.cmd` (double-click) finishes; `ImageViewer.exe` was compiled.
- [ ] *Open with* shows **"Image Viewer"** (not "Windows PowerShell"); no console window flashes.
- [ ] Edge and Chrome open an app window without tabs; Firefox opens with the dedicated profile, no tabs/toolbar.
- [ ] Paths with spaces, Cyrillic, `#`, `%`; a file on a network share (`\\server\share\…`).
- [ ] `-Default` opens Settings → Default apps at Image Viewer; after choosing it, double-click works.
- [ ] `install-windows.cmd -ListBrowsers` lists Chrome / Edge / Firefox (names from Settings > Default apps); `-Browser nonsense` stops before installing.
- [ ] `uninstall-windows.cmd` removes the *Open with* entry and `%LOCALAPPDATA%\ImageViewer`.
- [ ] Optional: `tests\launcher-windows.test.ps1` in Windows PowerShell 5.1 (runs the full dry run too).

### macOS

- [ ] `install/install-macos.sh` builds `~/Applications/Image Viewer.app`; it opens on Apple silicon and Intel.
- [ ] Finder: right-click → *Open With* → Image Viewer works; no Dock icon lingers.
- [ ] Default browser Chrome / Firefox / Safari (Safari falls back to another installed browser).
- [ ] `--default` sets Image Viewer as default for PNG/JPEG/…; otherwise Get Info → Change All works.
- [ ] Error case (e.g. `--browser Nope`) shows an alert from the app.
- [ ] `install-macos.sh --list-browsers` lists Safari and the other browsers; `--browser Nope` stops before building the app.
- [ ] `uninstall-macos.sh` removes the app.
