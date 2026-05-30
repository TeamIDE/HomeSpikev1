#!/usr/bin/env bash
# @file refresh.sh
# @description Dev-iteration deploy. Syncs the entire app/ tree to
#   /opt/home-spike/ and SIGTERMs the running HomeSpike so the next BFB
#   tap respawns with new code. Does NOT touch Shell.qml or reboot.
#   With DRAWER=1, also pushes the patched Drawer.qml and SIGKILLs
#   Lomiri so the new drawer code loads (you'll see the greeter).
#
# @status Stable.
# @issues SIGKILLing Lomiri logs the user out to the greeter — that's the
#   cost of getting a clean QML reload. Lomiri caches QML aggressively,
#   so a graceful restart doesn't reliably reload changed files.
# @todo None
#
# Usage:  PIN=<phablet-sudo-pin>            ./refresh.sh
#         PIN=<phablet-sudo-pin> DRAWER=1   ./refresh.sh
set -euo pipefail

[ -z "${PIN:-}" ] && { echo "usage: PIN=<sudo-pin> [DRAWER=1] $0"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UMBRELLA_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
WITH_DRAWER="${DRAWER:-0}"

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

  # Sync app tree into /opt/home-spike (wipe + replace so deletions propagate)
  rm -rf /opt/home-spike
  mkdir -p /opt/home-spike
  mv /tmp/home-spike-staging/* /opt/home-spike/
  # home-spike.desktop is owned by /usr/share/applications; lift it out
  if [ -f /opt/home-spike/home-spike.desktop ]; then
    mv /opt/home-spike/home-spike.desktop /usr/share/applications/home-spike.desktop
    chmod 644 /usr/share/applications/home-spike.desktop
  fi
  chmod 755 /opt/home-spike/home-spike
  chmod -R u=rwX,go=rX /opt/home-spike

  if [ \"$WITH_DRAWER\" = \"1\" ]; then
    test -f /usr/share/lomiri/Launcher/Drawer.qml.orig || cp /usr/share/lomiri/Launcher/Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml.orig
    cp /opt/home-spike/lomiri-overrides/Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml
    chmod 644 /usr/share/lomiri/Launcher/Drawer.qml
  fi

  mount -o remount,ro /

  # SIGTERM first so Qt can flush Settings to disk; SIGKILL after grace.
  pkill -TERM -f qmlscene.*home-spike || true
  for i in 1 2 3 4 5; do
    pgrep -f qmlscene.*home-spike >/dev/null || break
    sleep 0.2
  done
  pkill -KILL -f qmlscene.*home-spike || true

  if [ \"$WITH_DRAWER\" = \"1\" ]; then
    echo \"Restarting Lomiri so the new Drawer.qml gets reloaded...\"
    pkill -9 -f \"^lomiri --\" || true
  fi
'"

if [ "$WITH_DRAWER" = "1" ]; then
  echo "refreshed (incl. Drawer.qml). Lomiri restarting — unlock when greeter appears."
else
  echo "refreshed. tap BFB (or wait for autostart) to see changes."
fi
