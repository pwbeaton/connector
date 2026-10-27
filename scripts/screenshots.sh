#!/bin/bash
# Captures demo-mode screenshots on a small and a large iPhone simulator, in
# light and dark mode, so the design can be reviewed without a device.
#
# Usage:  scripts/screenshots.sh <path to App.app built for the simulator> <output folder>
# Screens come from $SCREENS (space-separated), matching the app's `-screen` launch argument.
set -euo pipefail

APP="$1"
OUT="$2"
SCREENS="${SCREENS:-today}"
mkdir -p "$OUT"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
RUNTIME=$(xcrun simctl list runtimes available | grep -E '^iOS ' | tail -n 1 \
  | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+')
echo "App: $BUNDLE_ID  Runtime: $RUNTIME"

# Prefer the smallest and largest current iPhones; fall back to whatever exists.
pick_type() {
  for name in "$@"; do
    if xcrun simctl list devicetypes | grep -qF "$name ("; then echo "$name"; return; fi
  done
  xcrun simctl list devicetypes | grep -E '^iPhone' | tail -n 1 | sed -E 's/ \(com\..*//'
}
SMALL=$(pick_type "iPhone SE (3rd generation)" "iPhone 16e" "iPhone 17")
LARGE=$(pick_type "iPhone 17 Pro Max" "iPhone 16 Pro Max" "iPhone 17 Pro")

capture_on() {
  local label="$1" type="$2"
  local udid
  udid=$(xcrun simctl create "shots-$label" "$type" "$RUNTIME")
  echo "== $label: $type ($udid)"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$udid" "$APP"
  for appearance in dark light; do
    xcrun simctl ui "$udid" appearance "$appearance"
    for screen in $SCREENS; do
      xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" \
        -demo YES -screen "$screen" -screenshots YES > /dev/null
      # Launch, demo sync, and first layout; 4 s was sometimes too short on a freshly booted simulator.
      sleep 7
      xcrun simctl io "$udid" screenshot --type=png "$OUT/$label-$appearance-$screen.png" > /dev/null
      echo "   $label-$appearance-$screen.png"
    done
  done
  xcrun simctl shutdown "$udid"
  xcrun simctl delete "$udid"
}

capture_on small "$SMALL"
capture_on large "$LARGE"
