#!/bin/sh
# Prints the UDID of an available iPhone simulator, so build commands never
# assume a device name. It picks the last iPhone listed, which belongs to the
# newest installed iOS runtime.
#
# Usage:  UDID="$(scripts/pick-simulator.sh)"
set -eu

udid="$(xcrun simctl list devices available \
  | grep -E '^[[:space:]]+iPhone' \
  | tail -n 1 \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' || true)"

if [ -z "$udid" ]; then
  echo "No available iPhone simulator found. Install one in Xcode → Settings → Components." >&2
  exit 1
fi

echo "$udid"
