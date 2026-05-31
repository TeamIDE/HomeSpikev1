#!/usr/bin/env bash
# @file install.sh
# @description Full HomeSpike install. Pushes the app tree to /opt/home-spike/,
#   backs up every Lomiri UI file we modify as .orig, and replaces it with
#   our copy from app/lomiri-overrides/. No sed surgery — `ls app/lomiri-
#   overrides/` lists every system file HomeSpike touches.
#
#   Reboots when done. Idempotent: re-run safely after a Lomiri OTA to
#   reapply every change.
#
# @status Stable. Tested on OnePlus Nord N100 (billie2) UT 24.04 noble.
# @issues Hardcodes /home/phablet — assumes the standard UT user. Adjust
#   if running on a multi-user UT setup.
# @todo None
#
# Usage:  PIN=<phablet-sudo-pin> ./install.sh
set -euo pipefail

[ -z "${PIN:-}" ] && { echo "usage: PIN=<sudo-pin> $0"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UMBRELLA_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"

if [ -n "${ADB:-}" ] && [ -x "$ADB" ]; then
  :
elif command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
elif [ -x "$UMBRELLA_ROOT/research/n100-be2012-crossflash/host-tools/platform-tools/adb" ]; then
  ADB="$UMBRELLA_ROOT/research/n100-be2012-crossflash/host-tools/platform-tools/adb"
else
  echo "ERROR: no adb found. install Android platform-tools or set ADB=<path>."
  exit 1
fi

echo "[1/4] adb=$ADB, checking device..."
"$ADB" devices | grep -q "device$" || { echo "ERROR: no device. plug in phone, enable developer mode."; exit 1; }

echo "[2/4] Pushing app tree to /tmp/home-spike-staging..."
"$ADB" shell "rm -rf /tmp/home-spike-staging" >/dev/null
"$ADB" push "$REPO_ROOT/app" /tmp/home-spike-staging >/dev/null

echo "[3/4] Remount rw, install app tree, replace Lomiri overrides..."
"$ADB" shell "echo '$PIN' | sudo -S sh -c '
  set -e
  mount -o remount,rw /

  # ----- HomeSpike app: sync whole tree into /opt/home-spike/ -----
  #       HomeSpike runs inside the lomiri process (loaded by Stage.qml
  #       at z=-2). No .desktop, no standalone wrapper.
  rm -rf /opt/home-spike
  mkdir -p /opt/home-spike
  mv /tmp/home-spike-staging/* /opt/home-spike/
  chmod -R u=rwX,go=rX /opt/home-spike
  # Clean up artifacts from older standalone-app installs.
  rm -f /usr/share/applications/home-spike.desktop

  # ----- Lomiri overrides: backup-and-replace each system QML file -----
  # Shell.qml: BFB rewire + autostart HomeSpike at shell startup
  test -f /usr/share/lomiri/Shell.qml.orig || cp /usr/share/lomiri/Shell.qml /usr/share/lomiri/Shell.qml.orig
  cp /opt/home-spike/lomiri-overrides/Shell.qml /usr/share/lomiri/Shell.qml
  chmod 644 /usr/share/lomiri/Shell.qml

  # Drawer.qml: long-press → context menu → add to HomeSpike
  test -f /usr/share/lomiri/Launcher/Drawer.qml.orig || cp /usr/share/lomiri/Launcher/Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml.orig
  cp /opt/home-spike/lomiri-overrides/Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml
  chmod 644 /usr/share/lomiri/Launcher/Drawer.qml

  # Spread.qml: home button in the right-swipe task switcher
  test -f /usr/share/lomiri/Stage/Spread/Spread.qml.orig || cp /usr/share/lomiri/Stage/Spread/Spread.qml /usr/share/lomiri/Stage/Spread/Spread.qml.orig
  cp /opt/home-spike/lomiri-overrides/Spread.qml /usr/share/lomiri/Stage/Spread/Spread.qml
  chmod 644 /usr/share/lomiri/Stage/Spread/Spread.qml

  # Stage.qml: spread.active binding + hide HomeSpike card in spread
  test -f /usr/share/lomiri/Stage/Stage.qml.orig || cp /usr/share/lomiri/Stage/Stage.qml /usr/share/lomiri/Stage/Stage.qml.orig
  cp /opt/home-spike/lomiri-overrides/Stage.qml /usr/share/lomiri/Stage/Stage.qml
  chmod 644 /usr/share/lomiri/Stage/Stage.qml

  # ----- Inbox file used by Drawer→HomeSpike IPC -----
  mkdir -p /home/phablet/.config/home-spike
  touch /home/phablet/.config/home-spike/pending-adds.txt
  chown -R phablet:phablet /home/phablet/.config/home-spike

  # ----- GSettings schema for the master kill-switch -----
  cp /opt/home-spike/system-settings-plugin/com.lomiri.HomeSpike.gschema.xml \
     /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml
  chmod 644 /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml
  glib-compile-schemas /usr/share/glib-2.0/schemas/

  # ----- System Settings plugin (Settings → Personal → HomeSpike) -----
  cp /opt/home-spike/system-settings-plugin/home-spike.settings \
     /usr/share/lomiri-system-settings/home-spike.settings
  chmod 644 /usr/share/lomiri-system-settings/home-spike.settings
  mkdir -p /usr/share/lomiri-system-settings/qml-plugins/home-spike
  cp /opt/home-spike/system-settings-plugin/PageComponent.qml \
     /usr/share/lomiri-system-settings/qml-plugins/home-spike/PageComponent.qml
  chmod 644 /usr/share/lomiri-system-settings/qml-plugins/home-spike/PageComponent.qml

  echo --- overrides installed ---
  for f in Shell.qml Launcher/Drawer.qml Stage/Spread/Spread.qml Stage/Stage.qml; do
    if [ -f /usr/share/lomiri/$f.orig ]; then
      echo "  /usr/share/lomiri/$f -- backup at .orig"
    fi
  done
  echo "  /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml -- new"
  echo "  /usr/share/lomiri-system-settings/home-spike.settings -- new"
  echo "  /usr/share/lomiri-system-settings/qml-plugins/home-spike/ -- new"
  ls /opt/home-spike/
  mount -o remount,ro /
'"

echo "[4/4] Rebooting device. Wait ~30s, unlock, HomeSpike should already be there."
"$ADB" shell "echo '$PIN' | sudo -S reboot" 2>&1 | grep -v '^\[sudo\]' || true
echo "done. installed."
