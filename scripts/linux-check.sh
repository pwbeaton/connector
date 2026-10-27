#!/bin/bash
# Compiles and tests the app's platform-neutral Swift code (Engine, Google, Sync, ...)
# on Linux, inside the official swift:6.2 Docker image. For cloud sessions without Xcode:
# it catches most compile and concurrency errors in seconds instead of a CI round trip.
# CI on macOS stays the authority (SwiftUI, Supabase, Keychain, and widgets are skipped here).
#
# Usage: scripts/linux-check.sh [test|build] [extra swift args]   (default: test)
# Needs Docker (`dockerd &`) and `docker pull swift:6.2-noble`.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$REPO/.linux-check"
mkdir -p "$WORK"
cp "$REPO/scripts/linux-check/Package.swift" "$WORK/Package.swift"
[ -d "$WORK/swift-crypto" ] || git clone -q --depth 1 --branch 3.15.1 https://github.com/apple/swift-crypto "$WORK/swift-crypto"

# Copy every file that doesn't import an Apple-only framework, with two Linux tweaks:
# URLRequest lives in FoundationNetworking, and CryptoKit is swift-crypto's Crypto.
rm -rf "$WORK/Sources/App" "$WORK/Tests/AppTests"
mkdir -p "$WORK/Sources/App" "$WORK/Tests/AppTests"
APPLE_ONLY='^import (SwiftUI|UIKit|Supabase|Security|WidgetKit|BackgroundTasks|AuthenticationServices|Charts)$'
copy() {
  local file=$1 dest=$2
  grep -Eq "$APPLE_ONLY" "$file" && return 0
  local out="$dest/$(echo "${file#"$REPO"/}" | tr '/' '_')"
  { printf '#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n'
    sed -e 's/^import CryptoKit$/import Crypto/' "$file"; } > "$out"
}
while IFS= read -r f; do copy "$f" "$WORK/Sources/App"; done < <(find "$REPO/App" "$REPO/Shared" -name '*.swift')
while IFS= read -r f; do copy "$f" "$WORK/Tests/AppTests"; done < <(find "$REPO/Tests" -name '*.swift')
cp "$REPO/scripts/linux-check/LinuxShims.swift" "$WORK/Sources/App/"
# Tests that read the app's Info.plist or test Apple-only code.
rm -f "$WORK/Tests/AppTests/"Tests_{AppGroupTests,NonceTests,AvatarTests}.swift

# The sandbox's HTTPS proxy runs on localhost, so share the host network and its CA bundle.
PROXY_ARGS=(--network host -e HTTPS_PROXY -e HTTP_PROXY -e NO_PROXY)
[ -f /root/.ccr/ca-bundle.crt ] && PROXY_ARGS+=(-v /root/.ccr/ca-bundle.crt:/ca.crt:ro -e GIT_SSL_CAINFO=/ca.crt -e SSL_CERT_FILE=/ca.crt)
CMD=${1:-test}; shift || true
docker run --rm "${PROXY_ARGS[@]}" -v "$WORK:/work" -w /work swift:6.2-noble swift "$CMD" "$@" 2>&1 \
  | grep -Ev '^\[[0-9]+/[0-9]+\]|^(Compiling|Emitting|Write |Building for|Planning build)|^✔ (Test [^ ]+\(|Suite )|^◇ '
exit "${PIPESTATUS[0]}"
