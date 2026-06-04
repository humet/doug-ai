#!/usr/bin/env bash
# Capture a screenshot of the booted simulator, downscaled for token economy.
#
# Usage:
#   shot.sh [output.png] [width]
#
# Defaults: writes to a timestamped file under /tmp and downscales to 400px wide.
# A simulator screenshot is ~1290px wide (~5k tokens to read); 400px is legible
# for layout/state checks at a fraction of the cost. Pass a larger width when
# pixel detail matters (e.g. 800), or 0 to keep full resolution.
source "$(dirname "$0")/lib.sh"
udid="$(booted_udid)"

out="${1:-/tmp/doug-shot.png}"
width="${2:-400}"

xcrun simctl io "$udid" screenshot "$out" >/dev/null 2>&1 || die "screenshot failed"

if [ "$width" != "0" ]; then
  # sips ships with macOS — no Pillow / Python needed.
  sips --resampleWidth "$width" "$out" >/dev/null 2>&1 || true
fi

# Report path + final pixel size so the caller knows what it's about to read.
size="$(sips -g pixelWidth -g pixelHeight "$out" 2>/dev/null \
  | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w"x"h}')"
echo "✓ $out ($size)"
