#!/bin/bash
# Downloads Satoshi (Indian Type Foundry, ITF Free Font License) into Shared/Fonts.
# The license allows embedding the fonts in the app but not sharing the files publicly,
# so they're git-ignored. Run this once after cloning. Without them the app uses the system font.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/satoshi.zip" "https://api.fontshare.com/v2/fonts/download/satoshi"
unzip -q "$tmp/satoshi.zip" -d "$tmp"
mkdir -p Shared/Fonts
for weight in Regular Medium Bold Black; do
  cp "$tmp"/Satoshi_Complete/Fonts/OTF/Satoshi-$weight.otf Shared/Fonts/
done
rm -rf "$tmp"
echo "Satoshi installed in Shared/Fonts. Run: xcodegen generate"
