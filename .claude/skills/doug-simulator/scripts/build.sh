#!/usr/bin/env bash
# Build Doug, or run its tests, with concise pass/fail output.
#
# Usage:
#   build.sh build              # build the app for the simulator
#   build.sh domain             # fast SPM domain tests (~0.15s, no simulator)
#   build.sh test [Class]       # full xcodebuild test, optionally one test class
#
# Mirrors the commands in CLAUDE.md so there is one source of truth.
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

cmd="${1:-build}"
DEST="platform=iOS Simulator,name=$DEFAULT_DEVICE"

# Print the last few error/failure lines from an xcodebuild log, then the verdict.
summarize() {
  local log="$1" status="$2"
  grep -E "error:|failed|Testing failed|\*\* (BUILD|TEST) (SUCCEEDED|FAILED) \*\*" "$log" \
    | tail -20 || true
  if [ "$status" -eq 0 ]; then echo "✓ ${cmd} succeeded"; else echo "✗ ${cmd} failed (exit $status)"; fi
  return "$status"
}

case "$cmd" in
  domain)
    swift test 2>&1 | tail -25 ;;
  build)
    log="$(mktemp)"
    set +e
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" build >"$log" 2>&1
    st=$?; set -e
    summarize "$log" "$st" ;;
  test)
    log="$(mktemp)"
    only=""
    [ -n "${2:-}" ] && only="-only-testing:${UITEST_TARGET%UITests}Tests/$2"
    set +e
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" $only test >"$log" 2>&1
    st=$?; set -e
    summarize "$log" "$st" ;;
  *)
    die "unknown command '$cmd' (use: build | domain | test)" ;;
esac
