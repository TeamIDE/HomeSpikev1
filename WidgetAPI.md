# WidgetAPI — v2.0 (TeamIDE first-party widgets, in-process QML)

> **Status:** scoping draft. v2.0 ships first-party widgets only — same
> code path as HomeSpike itself, runs in lomiri's process, no Click
> integration yet. v2.1 adds the out-of-process Click-widget API
> (Mir-surface compositing).
>
> **Scope:** rendering, layout, lifecycle, refresh, persistence, and
> the sample widget set HomeSpike ships in v2.0.

---

## Goal

Let HomeSpike host widgets — small QML surfaces (clock, battery, recent
mail, calendar agenda, etc.) — that live alongside icon tiles on the
home grid. v2.0 is **TeamIDE-first-party only**: HomeSpike ships the
widgets in its own payload, users can't write their own yet. The
contract we build here is what v2.1's third-party tier will plug into.

---

## Architecture

Widgets are QML files loaded into HomeSpike's process via `Loader`.
Same security posture as HomeSpike itself: full power, full trust,
runs as `phablet`. We accept this risk for first-party widgets;
sandboxing comes in v2.1 with the Mir-surface tier.

```
/opt/home-spike/widgets/
├── <widget-id>/                       (one directory per widget)
│   ├── widget.json                    (manifest)
│   ├── Widget.qml                     (the widget's UI)
│   ├── icon.svg                       (shown in the "add widget" picker)
│   └── (any other resources the widget needs)
└── ...
```

Naming convention: `<widget-id>` = reverse-domain (e.g. `dev.teamide.clock`).

---

## Manifest (`widget.json`)

Minimal v2.0 schema:

```json
{
    "id":          "dev.teamide.clock",
    "name":        "Clock",
    "description": "A clock face — analog or digital.",
    "version":     "1.0",
    "author":      "TeamIDE",
    "icon":        "icon.svg",
    "entry":       "Widget.qml",
    "sizes":       ["2x2", "4x2"],
    "default_size": "2x2",
    "refresh_seconds": 60,
    "tap_target": "application:///dev.teamide.clock.desktop"
}
```

Field meanings:
- `id` — globally unique, reverse-domain.
- `sizes` — array of WxH strings the widget can render at. Coordinate
  system = HomeSpike's existing grid cells (1 cell ≈ icon footprint).
- `default_size` — what `Add widget` uses on first placement.
- `refresh_seconds` — HomeSpike calls `widget.refresh()` at most this
  often when the widget is visible (capped to 10s minimum to protect
  battery). `0` means push-only.
- `tap_target` — URL fired when the user taps the widget (typically the
  parent app's `.desktop`). Optional — omit if the widget itself
  handles taps internally.

---

## Widget runtime API

Inside `Widget.qml`, HomeSpike exposes these to the root Item:

```qml
Item {
    id: widget
    anchors.fill: parent   // HomeSpike sets parent geometry for you

    // ---- Injected by HomeSpike ----
    // Geometry the widget should render to. Bound to the cell size the
    // user picked (e.g. 2x2 cells of HomeSpike's grid).
    // Read-only: widget.width, widget.height come from HomeSpike.

    // Current size string (matches one of the manifest's "sizes" entries).
    property string size: "2x2"

    // True while the widget's containing page is the current page in
    // HomeSpike's pageview. Use this to suspend timers / animations
    // when off-screen.
    property bool active: true

    // Edit-mode flag — true when the user is rearranging things.
    // Widgets can use this to grey themselves out, show a remove
    // badge, etc.
    property bool editMode: false

    // ---- Functions HomeSpike calls ----
    // Pull-refresh trigger (scheduled by HomeSpike's per-widget timer,
    // OR fired explicitly by the widget via pingRefresh()). Widget
    // implements this to re-read its data source.
    function refresh() { /* override */ }

    // ---- Signals the widget can emit ----
    // Bubble a "data changed, please redraw me" event out to HomeSpike
    // when push-style refresh applies (e.g. file watcher fired).
    signal pingRefresh()

    // Override the manifest's tap_target for a specific tap region.
    // Optional — leave unbound to fall through to manifest default.
    signal tapHandled(string url)
}
```

All standard QML/Qt APIs are available (file IO via `XMLHttpRequest`,
GSettings, Timer, Qt.labs.settings, etc). Widget rendering is just QML
— no special component palette to learn.

---

## Lifecycle

1. **Discovery** — at startup, HomeSpike scans
   `/opt/home-spike/widgets/*/widget.json` and builds an in-memory
   registry. Re-scan on user-triggered "Refresh widget list" (manual,
   in Settings → HomeSpike).
2. **Placement** — user enters edit mode, taps **+ Add widget**, picks
   from the registry, taps a free spot on the page. HomeSpike adds an
   entry to that page's persist with `{type: "widget", id, size, col, row}`.
3. **Instantiation** — when a page renders, each widget entry instantiates
   its `Widget.qml` via `Loader`.
4. **Visible vs off-page** — HomeSpike sets `widget.active = true` only
   for the current page's widgets. Off-page widgets get `active = false`
   and their refresh timer pauses.
5. **Refresh schedule** — HomeSpike maintains one `Timer` per visible
   widget instance, interval = `manifest.refresh_seconds` (min 10s).
   On tick, calls `widget.refresh()`. Widget can also `widget.pingRefresh()`
   to demand an out-of-cycle refresh (e.g. after a file-watcher event).
6. **Removal** — user taps the × badge in edit mode → entry removed
   from persist → `Loader` destroys the widget instance.

---

## Layout integration

Widgets coexist with icon tiles in the same per-page layout:

- **Auto-fill mode (default):** widgets are skipped from auto-flow.
  Pages with widgets behave like `snap` mode — explicit position
  required. (Open: should we just disallow widgets in auto-fill mode
  and force the user to switch? Decision pending; safest = allow but
  treat widget-occupied cells as "do not flow into".)
- **Snap-to-grid mode:** widget occupies its declared `WxH` block of
  cells starting at its `(col, row)`. Other tiles flow around occupied
  cells.
- **Place-anywhere mode:** widget gets `xFrac/yFrac` plus `wFrac/hFrac`
  (we extend the per-tile schema). Drag corners to resize.

Persistence extension (per-page bag, snap mode):

```json
{
  "snap": [
    {"appId": "phone", "col": 0, "row": 0},
    {"type": "widget", "id": "dev.teamide.clock", "size": "2x2", "col": 1, "row": 0},
    ...
  ]
}
```

`type: "widget"` is the new discriminator. Old entries without `type`
are still treated as `tile` (appId-driven).

---

## Edit mode UX additions

- **+ Add widget** button at the top of the edit-mode chrome (next to
  the existing Done pill).
- Tapping it opens a widget picker modal (scrollable grid of registered
  widgets with icon + name).
- Drop on a free spot on the current page → placement uses the widget's
  `default_size`.
- × badge on widget in edit mode (same as tiles).
- Resize handles on widget corners (only when the manifest declares
  multiple sizes). Snap to the nearest valid `WxH` from the manifest.

---

## Refresh model

Combination of push + pull, gated on visibility, capped on rate:

| Scenario                                  | What happens                       |
| ----------------------------------------- | ---------------------------------- |
| Widget is on the current page             | Timer ticks; `refresh()` called on schedule |
| Widget is on a non-current page           | Timer paused; `active = false`     |
| User swipes to widget's page              | `active → true`; one immediate `refresh()` then resume schedule |
| Widget fires `pingRefresh()` (push)       | Out-of-cycle `refresh()` if `active`; queued for next visibility if not |
| Multiple visible widgets refresh same time| Allowed; QML handles concurrency naturally |
| Refresh interval requested < 10s          | Clamped to 10s (battery floor)     |
| HomeSpike disabled via Settings toggle    | All widget timers stopped; widgets hidden |

---

## Sample widgets to ship in v2.0

To validate the API + give users something out-of-box. Three widgets:

1. **`dev.teamide.clock`** — analog or digital clock. Sizes: `2x2`,
   `4x2`. Refresh: 60s (the minute hand). Reads system time, no IPC.
2. **`dev.teamide.battery`** — battery level bar + percentage. Sizes:
   `2x1`. Refresh: 30s. Reads `/sys/class/power_supply/battery/capacity`.
3. **`dev.teamide.calendar-agenda`** — next 3 calendar events.
   Sizes: `2x2`, `4x2`. Refresh: 300s. Reads from EDS (Evolution Data
   Server, the UT calendar backend) via D-Bus.

All three exercise different data sources (none, file, D-Bus) so the
API surface gets stretched.

---

## Persistence model — extension to home-spike.conf

Today's per-page bag has `autoFill[]`, `snap[]`, `free[]`. Widgets
extend `snap[]` and `free[]` entries with a `type` field:

```json
{
  "snap": [
    {"appId": "phone", "col": 0, "row": 0},
    {"type": "widget", "widgetId": "dev.teamide.clock", "size": "2x2", "col": 1, "row": 0}
  ],
  "free": [
    {"appId": "phone", "xFrac": 0.1, "yFrac": 0.1},
    {"type": "widget", "widgetId": "dev.teamide.clock", "wFrac": 0.5, "hFrac": 0.3, "xFrac": 0.5, "yFrac": 0.1}
  ]
}
```

`autoFill` doesn't grow widget support in v2.0 (we just skip widgets
when populating auto-fill pages — open question on this).

Migration: existing entries with no `type` field continue to render
as tiles. Forward-compatible read; legacy HomeSpike installs reading
new pages just ignore widget entries silently (no rendering, no crash).

---

## Settings additions

New section in HomeSpike's settings overlay:

- **Widgets** — toggle each installed widget on/off globally (kill all
  instances of a widget that's misbehaving).
- **Widget refresh policy** — global cap "max refresh frequency"
  (default 30s; user can raise to 60s, 5min, 15min for battery).

---

## What this doc is NOT covering yet (deferred to v2.1+)

- **Click-app widget tier** — the out-of-process Mir-surface compositing
  story for third-party widgets. v2.0 is pure first-party.
- **Widget marketplace UI** — discovery / install / update of widgets
  beyond what HomeSpike ships. v2.0 widgets ship in HomeSpike's payload.
- **Widget configuration** — per-instance settings (e.g. "show seconds
  on the clock", "show next 5 events not 3"). v2.0 widgets are
  config-less; v2.1 adds a per-widget settings sheet.
- **Inter-widget communication** — widgets don't talk to each other.
  Each widget owns its own data.
- **Background data fetch** — when no widget instance is visible
  anywhere, no fetch happens. v2.x might add background daemons later.

---

## Open questions

1. **Widget sizes — fixed list or freeform?** I propose fixed (`1x1`,
   `2x1`, `2x2`, `4x2`, `4x4`) for layout sanity. Open to a free
   `WxH` if the design needs it.
2. **Auto-fill behavior** — disallow widgets in auto-fill mode, or
   keep but skip them from flow? Skip is friendlier but the math gets
   weird when you have a 4x2 widget on a flow-layout page.
3. **Resize gesture** — drag a corner (mobile-friendly?) vs long-press
   then choose size from a menu (matches iOS WidgetKit's edit flow)?
4. **Page-dot indicator behavior** — should pages with widgets get a
   different marker so the user knows which pages have heavier content?
5. **Per-widget enable toggle in HomeSpike Settings** — yes, useful
   kill-switch. Or skip and rely on user removing the widget from
   the home grid?
6. **Crash isolation** — first-party in-process means a buggy widget
   can hang HomeSpike. Acceptable for v2.0 since we ship the widgets;
   v2.1's out-of-process tier solves this for third-party.
7. **Versioning** — what happens when a widget's `widget.json` schema
   evolves? Maybe a top-level `schema_version` field on the manifest.

---

## What success looks like for v2.0

- Three TeamIDE widgets shipping in HomeSpike's payload.
- User can add/remove/resize them in edit mode.
- They auto-refresh on schedule, pause off-page.
- HomeSpike Settings has a per-widget kill-switch.
- All three widget types (no-data, file-data, D-Bus-data) work cleanly.
- `WidgetAPI.md` is the contract that v2.1's Click-app tier extends —
  same `Widget.qml` API, just hosted in a different process.
