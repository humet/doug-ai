#!/usr/bin/env bash
# Drive simulator-wide conditions for testing Doug under different states.
#
# Usage:
#   device.sh appearance <light|dark>
#   device.sh content-size <S|M|L|XL|XXL|XXXL|accessibility1..5>
#   device.sh push <title> <body>      # deliver a push to Doug
#   device.sh location <lat> <lng>
#   device.sh statusbar-clean          # 9:41, full battery/signal for clean shots
#   device.sh statusbar-clear          # revert status bar overrides
source "$(dirname "$0")/lib.sh"
udid="$(booted_udid)"
cmd="${1:-}"

case "$cmd" in
  appearance)
    [ -n "${2:-}" ] || die "appearance requires light|dark"
    xcrun simctl ui "$udid" appearance "$2" && echo "✓ appearance=$2" ;;
  content-size)
    [ -n "${2:-}" ] || die "content-size requires a size"
    xcrun simctl ui "$udid" content_size "$2" && echo "✓ content_size=$2" ;;
  push)
    [ -n "${3:-}" ] || die "push requires <title> <body>"
    payload="$(mktemp /tmp/doug-push.XXXX.json)"
    printf '{"aps":{"alert":{"title":%s,"body":%s},"sound":"default"}}' \
      "$(jq -Rn --arg s "$2" '$s')" "$(jq -Rn --arg s "$3" '$s')" >"$payload"
    xcrun simctl push "$udid" "$APP_BUNDLE_ID" "$payload" && echo "✓ pushed" ;;
  location)
    [ -n "${3:-}" ] || die "location requires <lat> <lng>"
    xcrun simctl location "$udid" set "$2,$3" && echo "✓ location=$2,$3" ;;
  statusbar-clean)
    xcrun simctl status_bar "$udid" override \
      --time "9:41" --batteryState charged --batteryLevel 100 \
      --cellularBars 4 --wifiBars 3 && echo "✓ status bar set" ;;
  statusbar-clear)
    xcrun simctl status_bar "$udid" clear && echo "✓ status bar cleared" ;;
  *)
    die "unknown command '$cmd'" ;;
esac
