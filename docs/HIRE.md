# Hire TeamIDE

This repo is what we ship for free. If you need work like it for a
device, port, app, or shell integration you can't get to yourself,
hire us.

## What we did here, concretely

Took stock Ubuntu Touch on a OnePlus Nord N100 — where the default
swipe-from-left gesture opens an app drawer and there is no home
screen — and replaced that flow with **HomeSpike**: a custom
fullscreen home surface that sits under every other app, shows the
user's chosen wallpaper, and renders all installed apps in a
4-wide icon grid. Along the way:

- **Reverse-engineered Lomiri's shell QML enough to safely patch it.**
  Located the `onShowDashHome` signal handler at `Shell.qml:681`, the
  `Component.onCompleted` block at `Shell.qml:259`, and the
  `activateApplication` function at `Shell.qml:217` — then wired our
  appid into the BFB tap target and the session-start autostart
  with two surgical `sed` edits.
- **Built an OTA-survivable install path.** Patches are idempotent
  (sentinel-based guards), `Shell.qml.orig` is preserved as a backup,
  and re-running `install.sh` after a system update re-applies the
  same changes cleanly. Same workflow we use for the gpg/ofono
  patches on the BE2012 cross-flash.
- **Made the home app use the *user's actual wallpaper*.** Reproduced
  Lomiri's own precedence — `AccountsService.backgroundFile` →
  `com.lomiri.Shell` gsettings → hardcoded default — including the
  bare-path-to-`file://`-URI fixup. The wallpaper updates the moment
  the user picks a new one in System Settings.
- **Reused the shell's own app-enumeration model** (`AppDrawerModel`
  from `Lomiri.Launcher 0.1`, sorted via `AppDrawerProxyModel` from
  the *separate* `Utils 0.1` plugin) so we get exactly the same app
  list the drawer would show, no parallel `.desktop` scanner to
  maintain.
- **Solved the import-path problem** that keeps non-shell apps from
  using shell-only QML modules. The `home-spike` wrapper script
  exports `QML2_IMPORT_PATH=/usr/lib/aarch64-linux-gnu/lomiri/qml`
  before exec'ing `qmlscene`, so `AccountsService`, `Lomiri.Launcher`,
  `Utils`, and friends all resolve for us the same way they resolve
  for Lomiri itself.
- **Documented the architecture honestly.** The README spells out
  what is and isn't yet handled (OTA reapply, long-edge-swipe gesture,
  surface-stack edge cases), and why each Lomiri patch is where it
  is. Anyone with a Lomiri device can read it and follow.

## What you can hire us to do

### Custom shell / launcher / home surface work
You want a different default UX on Ubuntu Touch, Plasma Mobile,
Phosh, Sailfish, or any Wayland-based mobile shell. We've patched
Lomiri at the QML level and know the gesture, focus, surface, and
lifecycle plumbing well enough to land changes that survive reboots
and OTAs.

### Ubuntu Touch app development (Click + Lomiri.Components, or QML)
QML apps targeting the UBports stack — including ones that need
escape hatches (custom apparmor, system-app install, shell-import
access) that the standard Click sandbox doesn't allow.

### Device rescue & enablement
You bought the wrong SKU. Your fleet has a model whose bootloader
nobody's unlocked. Your community port works on one variant and
silently fails on another. We figure out *why* and ship the fix as
something your team can run. (See our `n100-be2012-crossflash`
repo for what that looks like end-to-end.)

### Halium / Ubuntu Touch / Sailfish bringup
New device, missing driver, broken modem, flaky sensor. We work in
the Halium tree, `ofono-binder-plugin`, `libgbinder-radio`,
`lxc-android`, and the AppArmor/Click confinement layer.

### Reverse engineering low-level system components
Binary analysis with capstone, ARM64 patch derivation against a
moving target, symbol-less symbol hunting via string xrefs. The
ofonod patch in our BE2012 repo and the Lomiri QML patches here
are representative.

### macOS-native tooling for traditionally Windows-only workflows
Most of mobile device modding assumes a Windows host. We don't. If
your team is on Macs and your vendor docs say "use this .exe,"
we replace the .exe.

## Other things we've built

- **[n100-be2012-crossflash](https://github.com/dcherrera/n100-be2012-crossflash)** —
  end-to-end macOS-native install path for a carrier-locked OnePlus
  Nord N100 BE2012 the stock UBports installer rejects. EDL/Firehose
  driver, bootloader unlock, recovery gpg bypass, ofonod cellular
  patch — all reproducible.
- **[Group Bluetooth Audio](https://teamide.dev/products/group-audio)** —
  macOS app that plays synchronized audio to multiple Bluetooth
  speakers, headphones, or wired outputs at once, with drift
  correction and per-device volume control.
- **[Full product list](https://teamide.dev/products)** — everything
  currently shipping.
- **[Portfolio](https://dcherrera-portfolio-main.teamide.dev/)** —
  longer-form case studies and prior work.

## Engagement options

- **Spike (1–3 days).** Targeted diagnosis or proof-of-concept. You
  bring a clear question; we come back with an evidence-backed
  answer and a small repro.
- **Fixed-scope project (1–6 weeks).** Reproducible installer like
  this one, a clean port, an upstream-quality patch series. Defined
  deliverables, milestone-based.
- **Embedded consulting (retainer).** We work alongside your team
  for an agreed slice of the week. Best when there's ongoing
  unknown-unknowns work.
- **Open-source sponsorship.** Fund a specific upstream effort —
  the next device on UBports' supported list, the upstream Lomiri PR
  that lands a home-surface mechanism for everyone. Listed publicly,
  delivered to upstream maintainers, not to a private repo.

## Why TeamIDE

- **We ship reproducibly.** The README is the contract. If a third
  party with the same hardware can't follow the steps, we haven't
  finished. (This repo is the demo.)
- **We document what's load-bearing and what's incidental.** Each
  Lomiri patch in this repo has a sentinel comment and a paragraph
  explaining what it does and why it's safe to apply twice.
- **We respect upstream.** Where a patch-Lomiri-locally approach is
  a stopgap, we say so and point at the upstream-quality fix. We'd
  rather see this mechanism merged into Lomiri than keep a private
  fork alive.

## Contact

[teamide.dev/contact](https://teamide.dev/contact) for project
inquiries and engagement scoping.

For quick questions, lower-stakes chatter, or just to see what we're
working on, find us in [Discord](https://discord.gg/YVcsHXSCYG).

For open issues against *this specific repo*, please use
GitHub issues — keeps the technical thread public and discoverable.

If you want to back ongoing work financially (not hire us for a
project), that's at [teamide.dev/support](https://teamide.dev/support).
