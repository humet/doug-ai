#!/usr/bin/env bash
# Stream or capture Doug's logs from the booted simulator.
#
# Usage:
#   logs.sh tail [seconds]      # capture this app's logs for N seconds (default 8)
#   logs.sh errors [seconds]    # same, filtered to error/fault level
#
# Uses `simctl spawn log` scoped to Doug's process, so output stays relevant
# instead of the full system firehose.
source "$(dirname "$0")/lib.sh"
udid="$(booted_udid)"
cmd="${1:-tail}"
secs="${2:-8}"

predicate="process == \"Doug\""
case "$cmd" in
  tail)   level="default" ;;
  errors) level="default"; predicate="$predicate AND messageType >= 16" ;;  # 16=error, 17=fault
  *)      die "unknown command '$cmd'" ;;
esac

echo "capturing Doug logs for ${secs}s..." >&2
# `log stream` has no built-in duration flag; cap it with a background timeout.
xcrun simctl spawn "$udid" log stream --level "$level" --style compact \
  --predicate "$predicate" 2>/dev/null &
pid=$!
sleep "$secs"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
