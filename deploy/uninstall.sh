#!/usr/bin/env bash
# @file uninstall.sh
# @description Full HomeSpike uninstall. Restores each /usr/share/lomiri
#   file we replaced from its .orig backup, removes /opt/home-spike, the
#   .desktop file, and the cross-process inbox. Then reboots. Safe to run
#   even if install never happened — just prints "no backup found" per
#   missing backup and moves on.
#
#   Also strips any leftover HOME_SPIKE_* sentinel lines from Stage.qml
#   in case an older install.sh that used sed left them behind.
#
# @status Stable.
# @issues Does NOT delete /home/phablet/.config/home-spike/home-spike.conf
#   (your saved layout). If you want a clean wipe, remove it manually.
# @todo None
#
# Usage:  PIN=<phablet-sudo-pin> ./uninstall.sh
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

"$ADB" devices | grep -q "device$" || { echo "ERROR: no device."; exit 1; }

"$ADB" shell "echo '$PIN' | sudo -S sh -c '
  set -e
  mount -o remount,rw /

  for target in \
      /usr/share/lomiri/Shell.qml \
      /usr/share/lomiri/Launcher/Drawer.qml \
      /usr/share/lomiri/Stage/Spread/Spread.qml \
      /usr/share/lomiri/Stage/Stage.qml; do
    if test -f \${target}.orig; then
      mv \${target}.orig \${target}
      echo restored \${target}
    else
      echo no backup for \${target}
    fi
  done

  # Sweep any leftover HOME_SPIKE_* sentinel lines (from older sed-based installs).
  for marker in HOME_SPIKE_SPREAD_ACTIVE HOME_SPIKE_HIDE_IN_SPREAD HOME_SPIKE_AUTOSTART; do
    if grep -q \"\$marker\" /usr/share/lomiri/Stage/Stage.qml 2>/dev/null; then
      sed -i \"/\$marker/d\" /usr/share/lomiri/Stage/Stage.qml
      echo \"cleaned Stage.qml: \$marker\"
    fi
    if grep -q \"\$marker\" /usr/share/lomiri/Shell.qml 2>/dev/null; then
      sed -i \"/\$marker/d\" /usr/share/lomiri/Shell.qml
      echo \"cleaned Shell.qml: \$marker\"
    fi
  done

  rm -rf /opt/home-spike
  # Sweep any home-spike.desktop left behind from older standalone-app installs.
  rm -f /usr/share/applications/home-spike.desktop
  rm -rf /home/phablet/.config/home-spike/pending-adds.txt

  # ----- Remove gsettings schema + system-settings plugin -----
  if [ -f /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml ]; then
    rm -f /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml
    glib-compile-schemas /usr/share/glib-2.0/schemas/
    echo removed gschema
  fi
  rm -f /usr/share/lomiri-system-settings/home-spike.settings
  rm -rf /usr/share/lomiri-system-settings/qml-plugins/home-spike

  mount -o remount,ro /
'"

"$ADB" shell "echo '$PIN' | sudo -S reboot" 2>&1 | grep -v '^\[sudo\]' || true
echo "done. reverted."
