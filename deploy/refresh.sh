#!/usr/bin/env bash
# @file refresh.sh
# @description Dev-iteration deploy. Syncs the entire app/ tree to
#   /opt/home-spike/ and SIGTERMs the running HomeSpike so the next BFB
#   tap respawns with new code. Default mode touches nothing in /usr/share/.
#
#   With LOMIRI=1, ALSO replaces every Lomiri override file from
#   app/lomiri-overrides/ and SIGKILLs Lomiri so the new shell code
#   loads (you'll see the greeter — unlock to continue).
#
# @status Stable.
# @issues SIGKILLing Lomiri logs the user out to the greeter — that's the
#   cost of getting a clean QML reload. Lomiri caches QML aggressively,
#   so a graceful restart doesn't reliably reload changed files.
# @todo None
#
# Usage:  PIN=<phablet-sudo-pin>            ./refresh.sh
#         PIN=<phablet-sudo-pin> LOMIRI=1   ./refresh.sh
#         (legacy alias: DRAWER=1 also works)
set -euo pipefail

[ -z "${PIN:-}" ] && { echo "usage: PIN=<sudo-pin> [LOMIRI=1] $0"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UMBRELLA_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
# Accept either LOMIRI=1 (new) or DRAWER=1 (legacy) for the same behavior.
WITH_LOMIRI="${LOMIRI:-${DRAWER:-0}}"

if [ -n "${ADB:-}" ] && [ -x "$ADB" ]; then
  :
elif command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
elif [ -x "$UMBRELLA_ROOT/research/n100-be2012-crossflash/host-tools/platform-tools/adb" ]; then
  ADB="$UMBRELLA_ROOT/research/n100-be2012-crossflash/host-tools/platform-tools/adb"
else
  echo "ERROR: no adb found."; exit 1
fi

"$ADB" devices | grep -q "device$" || { echo "ERROR: no device."; exit 1; }

# Push the whole app/ tree to a staging location, then sync into /opt/home-spike/
"$ADB" shell "rm -rf /tmp/home-spike-staging" >/dev/null
"$ADB" push "$REPO_ROOT/app" /tmp/home-spike-staging >/dev/null

"$ADB" shell "echo '$PIN' | sudo -S sh -c '
  set -e
  mount -o remount,rw /

  # Sync app tree into /opt/home-spike (wipe + replace so deletions propagate).
  # HomeSpike now runs inside lomiri; no .desktop, no standalone wrapper.
  rm -rf /opt/home-spike
  mkdir -p /opt/home-spike
  mv /tmp/home-spike-staging/* /opt/home-spike/
  chmod -R u=rwX,go=rX /opt/home-spike
  rm -f /usr/share/applications/home-spike.desktop

  if [ \"$WITH_LOMIRI\" = \"1\" ]; then
    # Backup-and-replace each Lomiri override. Backups are created once
    # (the test -f guard); subsequent runs just overwrite the live file.
    test -f /usr/share/lomiri/Shell.qml.orig                || cp /usr/share/lomiri/Shell.qml                /usr/share/lomiri/Shell.qml.orig
    test -f /usr/share/lomiri/Launcher/Drawer.qml.orig      || cp /usr/share/lomiri/Launcher/Drawer.qml      /usr/share/lomiri/Launcher/Drawer.qml.orig
    test -f /usr/share/lomiri/Stage/Spread/Spread.qml.orig  || cp /usr/share/lomiri/Stage/Spread/Spread.qml  /usr/share/lomiri/Stage/Spread/Spread.qml.orig
    test -f /usr/share/lomiri/Stage/Stage.qml.orig          || cp /usr/share/lomiri/Stage/Stage.qml          /usr/share/lomiri/Stage/Stage.qml.orig

    cp /opt/home-spike/lomiri-overrides/Shell.qml   /usr/share/lomiri/Shell.qml
    cp /opt/home-spike/lomiri-overrides/Drawer.qml  /usr/share/lomiri/Launcher/Drawer.qml
    cp /opt/home-spike/lomiri-overrides/Spread.qml  /usr/share/lomiri/Stage/Spread/Spread.qml
    cp /opt/home-spike/lomiri-overrides/Stage.qml   /usr/share/lomiri/Stage/Stage.qml

    chmod 644 /usr/share/lomiri/Shell.qml \
              /usr/share/lomiri/Launcher/Drawer.qml \
              /usr/share/lomiri/Stage/Spread/Spread.qml \
              /usr/share/lomiri/Stage/Stage.qml

    # Sync the gsettings schema + system-settings plugin too. These rarely
    # change, but the LOMIRI=1 path is the only one that touches /usr, so
    # bundle them here rather than gating on a separate flag.
    cp /opt/home-spike/system-settings-plugin/com.lomiri.HomeSpike.gschema.xml \
       /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml
    chmod 644 /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml
    glib-compile-schemas /usr/share/glib-2.0/schemas/

    cp /opt/home-spike/system-settings-plugin/home-spike.settings \
       /usr/share/lomiri-system-settings/home-spike.settings
    chmod 644 /usr/share/lomiri-system-settings/home-spike.settings
    mkdir -p /usr/share/lomiri-system-settings/qml-plugins/home-spike
    cp /opt/home-spike/system-settings-plugin/PageComponent.qml \
       /usr/share/lomiri-system-settings/qml-plugins/home-spike/PageComponent.qml
    chmod 644 /usr/share/lomiri-system-settings/qml-plugins/home-spike/PageComponent.qml
  fi

  mount -o remount,ro /

  # HomeSpike now lives inside lomiri — restart lomiri to reload any QML
  # change. The previous "refresh HomeSpike without restarting lomiri"
  # path is gone; both modes restart lomiri.
  echo \"Restarting Lomiri so HomeSpike + Lomiri overrides reload...\"
  pkill -9 -f \"^lomiri --\" || true
'"

echo "refreshed. Lomiri restarting — unlock when greeter appears."
