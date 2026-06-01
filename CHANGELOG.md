# Changelog

All notable changes to HomeSpike are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
HomeSpike uses [semantic versioning](https://semver.org/).

## [Unreleased]

### Added
- **System Settings integration.** New entry at *Settings → Personal → HomeSpike* with a master on/off toggle. Flipping it takes effect live — no restart, no logout. When off, the phone reverts to stock Lomiri behavior (BFB opens the drawer, spread home button hides, "Add to HomeSpike" drawer menu hides, launcher panel stops auto-collapsing, HomeSpike's UI is invisible while the wallpaper stays).
- **gsettings schema** `com.lomiri.HomeSpike` (single `enabled` boolean key, default `true`). Single source of truth for the toggle. Survives HomeSpike crashes since the override files read it directly.
- **[`docs/ClickInstaller.md`](docs/ClickInstaller.md)** — scoping doc for a future Click package that would ship HomeSpike through OpenStore (one-tap install, no `PIN=… ./install.sh` dance).
- **Drawer view modes — Standard / A-Z / Categories.** New pill button under the drawer's search field cycles through three layouts: *Standard* (stock Lomiri flat alphabetical grid, default), *A-Z* (same icons sectioned by single-letter sticky headers), *Categories* (XDG-bucket sections — Internet, Office, Multimedia, Games, Utilities, Development, Settings, Other; empty buckets hidden). Built initially as a POC for UBports bounty issue #127 (since claimed by another contributor); shipping it as a HomeSpike feature regardless.

### Changed
- **Reworked the "go home" mechanism.** The previous design minimised every running app on `showHome()` and then tried to un-minimise them when the user switched back — that needed a grace timer, a focused-app snapshot, Mir-focus-echo handling, and an unminimise pass on every focus change. It also broke the right-edge spread (cards tapped to resume an app dropped to HomeSpike instead). New design: `showHome()` just promotes the wallpaper Loader to z:9999 so HomeSpike visually covers everything. Apps stay alive at their normal staged positions, hidden behind HomeSpike. When the user focuses any app again, `homeShown` drops, the Loader sinks to z:-2, and the app is already there at full size.
- `deploy/install.sh`, `deploy/refresh.sh`, `deploy/uninstall.sh` now also install/remove the gsettings schema (with `glib-compile-schemas`) and the system-settings plugin.

### Fixed
- **Right-edge spread broken after going home.** Tapping any app card in the spread (or the same app the user came from) dropped them back to HomeSpike instead of returning to the app. Root cause was the minimise-then-restore chain in the previous architecture; the rewrite above eliminates it.
- **Settings switch did nothing.** Lomiri.Components `Switch` fires `onTriggered` (not `onClicked`); the toggle is wired correctly now.

## [1.0] — 2026-05-30

First release.

### Added
- **HomeSpike home surface** loaded as a QML tree inside Lomiri's `Stage.qml` at the wallpaper layer (`z: -2`), replacing the original `Wallpaper` element. No separate process, no `.desktop`, no autostart.
- **Multi-page swipeable home grid** (1–5 pages, configurable in HomeSpike's own settings overlay).
- **Three placement modes** with per-mode saved layouts that survive mode switches:
  - *Auto-fill* — icons flow left-to-right with no gaps (default).
  - *Snap to grid* — icons sit on a 4-column grid but can leave gaps; drop on an occupied cell swaps with the occupant.
  - *Place anywhere* — fractional positioning, overlaps allowed.
- **Optional iOS-style dock** at the bottom (max 5 apps, persistent across pages, adjustable plate height). When enabled, Lomiri's left launcher panel auto-collapses so HomeSpike owns the full width.
- **Edit mode** (long-press a tile): drag-to-reorder, drag-to-edge auto-flips page, × badge hides an app from HomeSpike (stays installed), drag between dock and grid.
- **Home button in the right-edge spread** — drop straight back to HomeSpike from the task switcher.
- **Drawer integration**: long-press any app in Lomiri's drawer → "Add to HomeSpike" menu → it appears on your home grid within ~2 seconds (file-inbox IPC, no D-Bus).
- **App enumeration via `AppDrawerModel`** (same model the drawer uses) sorted A–Z via `AppDrawerProxyModel`.
- **Wallpaper inherits whatever you set in Settings → Background** (same `AccountsService.backgroundFile` precedence as stock Lomiri).
- **Per-mode auto-place on new install:** new apps auto-append to the last page in `autoFill`/`snap`; `free` mode skips since placement is intentionally manual.
- **Cross-process inbox** at `/home/phablet/.config/home-spike/pending-adds.txt`, polled ~1.5 s by HomeSpike.
- **Per-mode persistence** at `~/.config/home-spike/home-spike.conf` (`Qt.labs.Settings`). Holds page-data per mode, dock contents, hidden apps, page count, dock-bg height, placement mode.
- **Click installer scaffolding**: bash-based `deploy/install.sh`, `deploy/refresh.sh`, `deploy/uninstall.sh` driven over ADB with the phablet sudo PIN. Idempotent + OTA-survivable (re-run after a system update).

### Fixed
- **Apps stay alive when going home.** A late-cycle architectural fix: tapping the Ubuntu logo (BFB) or the spread home button now reliably returns to HomeSpike with running apps still resumable from the spread. Lomiri's staged mode is designed around always rendering one app full-screen — there was no "show desktop" concept until HomeSpike added one. (The mechanism this introduced was simplified further in Unreleased above.)
- **Free-mode placement quantised to a grid** when it shouldn't have. Caused by `ListModel` inferring the `xFrac` role as `int` from the first appended row (`-1`), which truncated subsequent fractional writes. Fixed by using `-0.5` as the unset sentinel so the role is `real` from the start.
- **Drag drop position was offset half a row.** `(x, y)` came in as DragController-local but the renderer applied them to pageDelegate-local. New `_toPagesViewLocal()` helper subtracts the offset.
- **Tile re-taps within ~800 ms after `showHome()`** were classified as Mir focus-echoes and ignored, so HomeSpike stayed stuck on top. Fixed via an explicit `launchRequested` signal from HomeSpike tiles that drops `homeShown` immediately. (Mechanism fully removed in Unreleased.)
- **Settings dialog hidden behind launcher panel** when the dock was disabled. SettingsOverlay + ConfirmRemoveOverlay now carry `leftReserve` and shift their centred card right by half that.
- **Icon column cut off on the left** when launcher was visible. New `leftReserve` property is wired from Lomiri's `launcher.visibleWidth` into HomeSpike's grid/dock/dots insets.

### Lomiri files modified (full overrides, no sed)
- `/usr/share/lomiri/Shell.qml` — BFB rewire to `stage.showHome()`; `launcher.lockedVisible` also ORs in `stage.homeShown` and ANDs out `stage.homeSpikeDockEnabled`.
- `/usr/share/lomiri/Stage/Stage.qml` — `Wallpaper` element replaced with a `Loader` pointing at `/opt/home-spike/main.qml`; exposes `homeShown`, `homeSpikeDockEnabled`, `launcherLeftMargin` to children/siblings; wires the spread's `homeRequested` signal to `showHome()`.
- `/usr/share/lomiri/Stage/Spread/Spread.qml` — home button at the bottom-centre of the right-edge spread.
- `/usr/share/lomiri/Launcher/Drawer.qml` — long-press context menu with an "Add to HomeSpike" item that appends an `appId` to the inbox file.

### Tested on
- OnePlus Nord N100 (`billie2`, aarch64) running Ubuntu Touch 24.04 noble.

---

[Unreleased]: https://github.com/TeamIDE/HomeSpikev1/compare/v1.0.1...HEAD
[1.0]: https://github.com/TeamIDE/HomeSpikev1/releases/tag/v1.0.0
