# ClickInstaller — scoping doc

> Status: **draft / not yet built.** Path to ship HomeSpike on OpenStore
> as a tap-to-install Click package, replacing the `PIN=… ./install.sh`
> developer-mode dance.

---

## Goal

Let a regular Ubuntu Touch user install HomeSpike the same way they
install anything else: search OpenStore → tap **Install** → open the app
→ tap one button → reboot → HomeSpike is the home screen. No developer
mode, no ADB, no PIN typing, no terminal.

The Click package does **not** *become* HomeSpike. HomeSpike has to live
inside the lomiri process (loaded by `Stage.qml`'s `Loader` at the
wallpaper layer), so it can't be a sandboxed app surface. Instead, the
Click ships an **installer GUI** that drops HomeSpike's QML into
`/opt/home-spike/` and replaces the four Lomiri shell files — exactly
what `deploy/install.sh` does today, but driven by tap-a-button +
`pkexec` instead of `PIN=… ./install.sh` over ADB.

Same idempotent install/uninstall logic; same `.orig` backups; just a
different driver.

---

## Precedent

[UT Tweak Tool](https://open-store.io/app/ut-tweak-tool.sverzegnassi)
ships exactly this kind of thing — remounts root, modifies system
files — and lives on OpenStore. Its AppArmor file (verbatim from
[gitlab](https://gitlab.com/myii/ut-tweak-tool/-/blob/master/click/)):

```json
{
  "template": "unconfined",
  "policy_version": 20.04,
  "policy_groups": []
}
```

That's the entire trick. The path is well-trodden; we don't need to
invent anything new at the packaging level.

---

## Click package layout

```
home-spike-installer/                          (Clickable project root)
├── clickable.yaml                             (build config)
├── manifest.json.in                           (templated)
├── home-spike-installer.apparmor              (unconfined)
├── home-spike-installer.desktop               (launcher entry)
├── home-spike-installer.svg                   (icon)
├── qml/
│   ├── Main.qml                               (installer UI)
│   ├── InstallerActions.qml                   (install/uninstall logic)
│   └── StatusReporter.qml                     (per-step progress display)
└── payload/                                   (HomeSpike itself, vendored)
    ├── app/                                   (copy of HomeSpike's app/)
    │   ├── main.qml
    │   ├── persistence/, models/, drag/, tiles/, chrome/, overlays/, …
    │   ├── lomiri-overrides/
    │   │   ├── Shell.qml
    │   │   ├── Stage.qml
    │   │   ├── Spread.qml
    │   │   └── Drawer.qml
    │   └── system-settings-plugin/
    │       ├── com.lomiri.HomeSpike.gschema.xml   (gsettings schema)
    │       ├── home-spike.settings                (plugin manifest)
    │       └── PageComponent.qml                  (plugin UI page)
    └── version.json                           ({"version": "1.0", …})
```

The `payload/` directory is the entire HomeSpike source tree at the
version we're shipping. The Click installs it to
`/opt/home-spike-installer/payload/` and the install action copies from
there into `/opt/home-spike/` + `/usr/share/lomiri/…`. Bumping
HomeSpike's version = re-bundling + new Click revision.

---

## manifest.json (templated)

```json
{
  "name": "home-spike-installer.teamide",
  "title": "HomeSpike Installer",
  "description": "Install/uninstall HomeSpike — a real home screen for Ubuntu Touch",
  "framework": "ubuntu-sdk-20.04",
  "architecture": "all",
  "icon": "home-spike-installer.svg",
  "hooks": {
    "home-spike-installer": {
      "apparmor": "home-spike-installer.apparmor",
      "desktop":  "home-spike-installer.desktop"
    }
  },
  "version": "@VERSION@",
  "maintainer": "TeamIDE <hello@teamide.dev>"
}
```

`architecture: "all"` — HomeSpike is pure QML, no native code, so the
Click is per-arch-agnostic. Smaller package, single submission covers
aarch64 / armhf / amd64.

---

## AppArmor

```json
{
  "template": "unconfined",
  "policy_version": 20.04,
  "policy_groups": []
}
```

Same exact file as UT Tweak Tool. Unconfined means the app runs as the
`phablet` user with no AppArmor restrictions, but **still no root
privileges by default** — that's what `pkexec` is for.

---

## Installer UI (QML)

Single-page Lomiri-styled QML. Three primary buttons + a status pane:

```
┌───────────────────────────────────────────┐
│ HomeSpike Installer                       │
├───────────────────────────────────────────┤
│ Status: HomeSpike is currently:           │
│   [ NOT INSTALLED | INSTALLED v1.0 |      │
│     INSTALLED OLDER VERSION (v0.9) ]      │
│                                           │
│ [ Install ]   [ Reinstall ]               │
│ [ Uninstall ]                             │
│                                           │
│ Last run:                                 │
│ ┌───────────────────────────────────────┐ │
│ │ [step-by-step output from pkexec'd    │ │
│ │  install script — read-only log]      │ │
│ └───────────────────────────────────────┘ │
│                                           │
│ After install/uninstall a reboot is       │
│ required to finish.   [ Reboot now ]      │
└───────────────────────────────────────────┘
```

State detection (on app launch, before showing buttons):
- `NOT INSTALLED` — `/opt/home-spike/main.qml` missing
- `INSTALLED v1.0` — present, version.json matches Click's payload
- `INSTALLED OLDER VERSION` — present, but version mismatch → show
  Reinstall instead of Install

`Install` and `Reinstall` invoke the same backend script with pkexec;
`Reinstall` is a label change to communicate "this'll overwrite what
you have" to the user.

---

## Install flow (what the Install button does)

1. UI calls `pkexec /opt/click.ubuntu.com/home-spike-installer.teamide/current/scripts/install` (path varies; resolved at runtime).
2. Polkit prompts the user for their **phablet password** (not a custom PIN — system password).
3. `install` script (sh, same logic as today's `deploy/install.sh` minus the ADB plumbing):
   - `mount -o remount,rw /`
   - `rm -rf /opt/home-spike && mkdir -p /opt/home-spike`
   - `cp -r $CLICK_DIR/payload/app/* /opt/home-spike/`
   - `chmod -R u=rwX,go=rX /opt/home-spike`
   - For each of the 4 Lomiri files: backup `.orig` (if missing), copy the override.
   - Install `com.lomiri.HomeSpike.gschema.xml` to `/usr/share/glib-2.0/schemas/`, run `glib-compile-schemas` to register.
   - Install `home-spike.settings` to `/usr/share/lomiri-system-settings/`.
   - Install `PageComponent.qml` to `/usr/share/lomiri-system-settings/qml-plugins/home-spike/`.
   - `mkdir -p /home/phablet/.config/home-spike && touch …/pending-adds.txt`
   - `mount -o remount,ro /`
   - exit 0
4. UI parses script stdout line-by-line, feeds the status pane.
5. On success: enable the **Reboot now** button. (HomeSpike only takes
   effect after a lomiri restart; cleanest UX is a reboot.)

---

## Uninstall flow

Same shape as install, just runs the inverse:
- `mount -o remount,rw /`
- For each backed-up `.orig`: `mv …/file.orig …/file`
- `rm -rf /opt/home-spike`
- `rm -f /home/phablet/.config/home-spike/pending-adds.txt`
- `rm -f /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml`; `glib-compile-schemas /usr/share/glib-2.0/schemas/`
- `rm -f /usr/share/lomiri-system-settings/home-spike.settings`
- `rm -rf /usr/share/lomiri-system-settings/qml-plugins/home-spike`
- Leave `~/.config/home-spike/home-spike.conf` (user's saved layout) alone.
- `mount -o remount,ro /`

Plus the obvious: **uninstalling the Click package itself** should
trigger the uninstall script first, otherwise the user removes the
installer GUI but HomeSpike remains in `/opt`. Click hooks have an
`uninstall` hook for this — it runs in the app's confinement so it
can't itself touch `/usr`, but it can pop a notification or fire a
desktop notification telling the user to run uninstall before removing.
(Open question — see below.)

---

## OTA-survivability story

Every UT OTA wipes `/usr/share/lomiri/` overrides because the rootfs
gets re-flashed. After an OTA:
- HomeSpike's `/opt/home-spike/` survives (`/opt` is on the writable
  partition).
- The four Lomiri override files are gone, so the user sees stock
  Lomiri again.

Solution: the installer app **detects this on launch** by checking
whether `/usr/share/lomiri/Shell.qml.orig` exists. If `/opt/home-spike`
is present but `Shell.qml.orig` is missing → state =
`OVERRIDES_WIPED_BY_OTA`, show a single big button: **"Reapply after
update"**. One tap, pkexec, done.

For extra polish: register a tiny systemd `--user` service that runs at
session start, checks for the same condition, and pings the installer
icon with an unread badge. Skip for v1 of the installer.

---

## OpenStore submission steps

1. Build with `clickable build` for `framework: ubuntu-sdk-20.04`,
   `arch: all`. Output is a single `.click` file.
2. Tag the source repo (already public at
   github.com/TeamIDE/HomeSpikev1) for the version we're shipping.
3. Heads-up post in the [OpenStore Telegram](https://t.me/UBportsStore)
   before uploading: *"Going to submit HomeSpike Installer, unconfined
   Click, modifies four Lomiri shell QML files via pkexec — same
   pattern as UT Tweak Tool. Source at … Looking for a reviewer."*
4. Upload via [open-store.io/submit](https://open-store.io/submit),
   point at the GitHub repo for review.
5. Manual review by an OpenStore reviewer (a UBports core dev or
   trusted contributor). Expect questions about:
   - Why each of the four Lomiri files is replaced wholesale (we can
     point at the override files in the source tree — each one has a
     `// HomeSpike:` block explaining the patch).
   - Whether `.orig` backups + uninstaller fully restore state. (Yes.)
   - OTA story.
6. Iterate on review feedback. Once approved, app is publicly listed.
7. Add OpenStore badge to README.

---

## Open questions / deferred decisions

- **Click uninstall hook** — can a confined Click uninstall hook spawn
  pkexec for the system cleanup? If not, fallback is "show a notification
  on uninstall: please open the app and tap Uninstall before removing".
  Needs validation against current UT confinement rules.
- **Pkexec policy file** — do we need to ship a custom polkit `.policy`
  for nicer auth prompt text (`"Install HomeSpike (a custom home screen)"`)
  vs the default `"Authentication is required to run this program"`?
  Polkit files install under `/usr/share/polkit-1/actions/`, which the
  Click can write (it's unconfined). Nice-to-have for v1, not critical.
- **Per-arch packaging vs `arch: all`** — confirm pure QML works as
  `arch: all` on noble. Test on aarch64 + armhf reference units.
- **Reviewer pushback risk** — replacing four shell QML files is
  bigger surface area than anything currently on OpenStore. Worth a
  pre-submission conversation with @Keneda (the UBports dev who
  replied on the forum) — they already understand the use case.
- **Bundled vs fetched payload** — current plan bundles HomeSpike inside
  the Click. Alternative: Click is tiny, fetches latest HomeSpike tarball
  from github.com/TeamIDE/HomeSpikev1/releases on install. Pros: smaller
  Click, no rev bump per HomeSpike change. Cons: needs net access at
  install time, security review harder (reviewer can't see what's
  actually being installed). Bundled is safer.
- **In-app vs separate Click** — could the installer also be HomeSpike's
  settings UI ("manage placement modes, add widgets, etc")? Tempting,
  but mixes concerns and complicates the Click confinement story.
  Better to keep installer minimal; HomeSpike's own settings stay
  in-process where they are now.

---

## Risks

- **Manual review may stall or reject.** Mitigation: lead with
  Telegram conversation, point at UT Tweak Tool as precedent, offer
  to address whatever the reviewer flags.
- **A future Lomiri release shifts QML enough that one of our four
  overrides breaks.** Mitigation: installer's status pane runs a
  sanity check after applying — `journalctl --user -u lomiri --since
  "1 minute ago" | grep -i error` — if there are QML errors, show a
  warning + offer one-tap uninstall.
- **User runs Install while in greeter or low-battery.** Mitigation:
  installer disables the buttons until shell is idle + battery > 20%.
- **The Click + the legacy `install.sh` flow coexist.** Users running
  HomeSpike via the bash installer should be able to switch to the
  Click without surprise. Mitigation: installer's state detection
  treats "manually installed" the same as "Click-installed" because
  both leave the same files in place.

---

## What this doc is not

- Not the final UI mock. The button layout above is illustrative; real
  design pass when we start building.
- Not the v2 / widget API. Widgets ship via their own Click packages
  using the widget API contract (separate spec).
- Not a commitment to ship the installer before v2 — that's the
  scheduling call to make later.
