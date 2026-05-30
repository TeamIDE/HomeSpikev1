#!/usr/bin/env bash
# @file install.sh
# @description Full HomeSpike install. Pushes the app tree to /opt/home-spike/,
#   replaces /usr/share/lomiri/Launcher/Drawer.qml with our patched copy,
#   sed-patches /usr/share/lomiri/Shell.qml for BFB-rewire + autostart,
#   creates the cross-process inbox file, and reboots. Idempotent — safe
#   to re-run after a Lomiri OTA to reapply every change.
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

echo "[3/4] Remount rw, install app tree, patch Shell.qml + Drawer.qml..."
"$ADB" shell "echo '$PIN' | sudo -S sh -c '
  set -e
  mount -o remount,rw /

  # ----- HomeSpike app: sync whole tree into /opt/home-spike/ -----
  rm -rf /opt/home-spike
  mkdir -p /opt/home-spike
  # Move the app tree, then lift out files that live elsewhere on the system.
  mv /tmp/home-spike-staging/* /opt/home-spike/
  mv /opt/home-spike/home-spike.desktop /usr/share/applications/home-spike.desktop
  chmod 755 /opt/home-spike/home-spike
  chmod -R u=rwX,go=rX /opt/home-spike
  chmod 644 /usr/share/applications/home-spike.desktop

  # ----- Shell.qml: BFB rewire + autostart -----
  test -f /usr/share/lomiri/Shell.qml.orig || cp /usr/share/lomiri/Shell.qml /usr/share/lomiri/Shell.qml.orig
  sed -i \"s|onShowDashHome: showHome()|onShowDashHome: shell.activateApplication(\\\"home-spike\\\")|\" /usr/share/lomiri/Shell.qml
  if ! grep -q HOME_SPIKE_AUTOSTART /usr/share/lomiri/Shell.qml; then
    sed -i \"/finishStartUpTimer\\.start();/a\\        shell.activateApplication(\\\"home-spike\\\"); // HOME_SPIKE_AUTOSTART\" /usr/share/lomiri/Shell.qml
  fi

  # ----- Drawer.qml: long-press → context menu → add to HomeSpike -----
  test -f /usr/share/lomiri/Launcher/Drawer.qml.orig || cp /usr/share/lomiri/Launcher/Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml.orig
  cp /opt/home-spike/lomiri-overrides/Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml
  chmod 644 /usr/share/lomiri/Launcher/Drawer.qml

  # ----- Inbox file used by Drawer→HomeSpike IPC -----
  mkdir -p /home/phablet/.config/home-spike
  touch /home/phablet/.config/home-spike/pending-adds.txt
  chown -R phablet:phablet /home/phablet/.config/home-spike

  echo --- BFB patch ---
  grep -n onShowDashHome /usr/share/lomiri/Shell.qml
  echo --- autostart patch ---
  grep -n -A1 finishStartUpTimer /usr/share/lomiri/Shell.qml
  echo --- app tree installed ---
  ls /opt/home-spike/
  mount -o remount,ro /
'"

echo "[4/4] Rebooting device. Wait ~30s, unlock, HomeSpike should already be there."
"$ADB" shell "echo '$PIN' | sudo -S reboot" 2>&1 | grep -v '^\[sudo\]' || true
echo "done. installed."
