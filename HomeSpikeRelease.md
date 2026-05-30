# HomeSpike — a real home screen for Ubuntu Touch

> Title for the post — pick whichever fits the venue:
>
> **UBports forum:** `[Release] HomeSpike — replaces the default Lomiri swipe-from-left drawer with an iOS-style home screen (multi-page, dock, drag-to-reorder)`
>
> **r/UbuntuTouch / r/mobilelinux:** `I built a proper home screen for Ubuntu Touch — multi-page, dock, drag-to-reorder, integrates with the Lomiri drawer`

---

## What it is

HomeSpike is a fullscreen home surface for **Ubuntu Touch (Lomiri)** that replaces "drawer-as-default" with what most people actually expect from a phone: a wallpapered home grid you land on after unlock, swipeable pages of icons, an iOS-style dock, and an edit mode where you long-press to drag icons around or remove them. New apps you install auto-add to your last page. The Lomiri drawer is still there (the patched long-press inside it gives you an "Add to HomeSpike?" prompt), but it's no longer the first thing you see.

I built it because Ubuntu Touch in 2014 made a bet on "scopes as cards" replacing home screens with widgets, and that bet hasn't aged well. Every other mobile Linux shell since (Plasma Mobile, Phosh, even Android-via-Halium) has done the opposite. After daily-driving UT on a OnePlus Nord N100 and finding myself wanting *somewhere to put apps in an order I chose*, I stopped wishing for it and wrote it.

## How it works

It's all QML on top of stock Lomiri — no shell fork. Two surgical patches to `/usr/share/lomiri/Shell.qml` rewire the Ubuntu-logo button to launch HomeSpike instead of the drawer, and auto-start HomeSpike at shell startup so it's the visible surface after unlock. A third patch to `/usr/share/lomiri/Launcher/Drawer.qml` adds the long-press → "Add to HomeSpike?" dialog. Original files are backed up as `.orig` and `uninstall.sh` cleanly reverts everything. Installer is idempotent and OTA-survivable (re-run after a system update).

HomeSpike itself reuses Lomiri's own primitives instead of reinventing: app inventory comes from `AppDrawerModel` (the same model the drawer uses), wallpaper comes from `AccountsService.backgroundFile` (the same one Settings writes when you change wallpaper), icons render with `LomiriShape` (same rounded-rect tile primitive). State (icon order per page, dock contents, hidden apps, page count, dock-enabled) persists to `~/.config/home-spike/home-spike.conf` via `Qt.labs.Settings`. The Drawer→HomeSpike "add" is a file-inbox the running HomeSpike polls every 1.5 seconds — no D-Bus dance, just a file.

## Features

- Multi-page swipeable home (1–5 pages, configurable)
- Optional iOS-style dock at the bottom (max 5 apps, persistent across pages)
- Edit mode (long-press): drag-to-reorder, drag-to-edge auto-flips page, X-badge removes an icon (stays installed, just hidden from home)
- Drag between dock and grid in both directions
- Wallpaper inherits whatever you set in Settings → Background
- New installs auto-append to the last page; uninstalled apps silently drop
- Long-press an app in the swipe-left drawer → "Add to HomeSpike?" prompt → it appears on your home within ~2 seconds
- Per-arch portable wrapper script (aarch64 / armhf / x86_64) — no device-specific assumptions

## Tested on

OnePlus Nord N100 (`billie2`), Ubuntu Touch 24.04 noble. The design is generic to Lomiri 24.04 — should work on every device on that channel. If you try it on something else, please let me know.

## How to install

Currently distributed as a self-hosted installer (not OpenStore — see "Why not OpenStore" below). Phone connected via adb, developer mode on:

```sh
git clone <repo url>
cd HomeSpike
PIN=<your-phablet-sudo-pin> ./deploy/install.sh
```

To revert:

```sh
PIN=<your-phablet-sudo-pin> ./deploy/uninstall.sh
```

## Why not OpenStore

OpenStore ships Click packages, which are AppArmor-sandboxed and explicitly cannot modify system files, remount `/` rw, install outside their sandbox, or autostart as the shell's home surface — i.e., every single thing that makes HomeSpike *the home* rather than *an app you open*. A confined Click version would just be "HomeSpike Launcher: an app drawer you have to tap to enter," which loses 90% of the value. So this ships as a self-hosted installer for now. A clean long-term answer is upstreaming the home-surface mechanism into Lomiri proper — I'd like to do that once the design has settled in real-world use.

## Caveats up front

- **Modifies Lomiri shell files.** Read `install.sh` before running. Backups are made; `uninstall.sh` restores them.
- **OTA wipes patches.** Re-run `install.sh` after any system update. Takes a couple seconds.
- **Removes the OpenStore-link long-press in the drawer.** That gesture now goes to "Add to HomeSpike?" instead. Can be restored as a different gesture later if there's demand.
- **No widget API yet.** This release is the home surface itself. A widget system (with a real provider API) is the next milestone — current QML is the scaffolding for an eventual ImGui+Lua reimplementation that'll host third-party widgets.

## Source + issues

GitHub / Gitea: **<repo url here>**

License: GPL-2.0-or-later. No warranty. PRs welcome — especially "tested on `<your device>`" confirmations and Lomiri-version-drift fixes for the sed patch sites.

## TL;DR

> "I wanted a home screen on Ubuntu Touch. UT doesn't really have one — the
> drawer is the default surface and there's no place to arrange icons how
> you want. So I wrote one. It's a QML app + three small Lomiri shell
> patches. Multi-page, dock, drag-to-reorder, long-press in the system
> drawer adds apps to it. Backups + uninstaller included. Source linked
> below."
