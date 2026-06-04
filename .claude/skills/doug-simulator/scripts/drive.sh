#!/usr/bin/env bash
# Drive Doug's UI semantically via the XCUITest driver (DougDriverUITests).
# Executes an ordered step list in a single app launch and prints the structured
# result: per-step pass/fail plus the resulting accessibility tree.
#
# Usage:
#   drive.sh '<steps-json>'      # inline JSON array of steps
#   drive.sh -f steps.json       # steps from a file
#
# Step schema (see DougUITests/DougDriverUITests.swift for the full list):
#   [{"action":"tap","label":"Feed & Refrigerate"},
#    {"action":"assertExists","label":"Levain"},
#    {"action":"describe"}]
#
# Note: this runs `xcodebuild test`, so each call incrementally builds and
# launches a test runner (slower than a screenshot). Put a whole flow in one
# call rather than one call per tap.
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

if [ "${1:-}" = "-f" ]; then
  [ -f "${2:-}" ] || die "file not found: ${2:-}"
  steps="$(cat "$2")"
else
  steps="${1:-}"
  [ -n "$steps" ] || die "provide a steps JSON array (or -f file.json)"
fi

# Validate JSON early so failures are obvious, not buried in a build log.
echo "$steps" | jq -e 'type == "array"' >/dev/null 2>&1 || die "steps must be a JSON array"

DEST="platform=iOS Simulator,name=$DEFAULT_DEVICE"
log="$(mktemp)"

# TEST_RUNNER_-prefixed vars are forwarded by Xcode to the test runner process,
# where the driver reads DOUG_DRIVER_STEPS from the environment.
set +e
TEST_RUNNER_DOUG_DRIVER_STEPS="$steps" \
  xcodebuild test \
    -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" \
    -only-testing:"$UITEST_TARGET/DougDriverUITests/testRunSteps" \
    >"$log" 2>&1
st=$?
set -e

# Extract the structured result emitted between the driver's markers.
result="$(sed -n '/===DOUG_DRIVER_RESULT===/,/===END_DOUG_DRIVER_RESULT===/p' "$log" \
  | sed '1d;$d')"

if [ -z "$result" ]; then
  echo "✗ no driver result found — build or launch likely failed:" >&2
  grep -E "error:|Testing failed|Compiling|\*\* TEST" "$log" | tail -15 >&2
  exit "${st:-1}"
fi

# Concise per-step summary, then the accessibility tree.
echo "$result" | jq -r '.steps[] | "\(if .status=="ok" then "✓" else "✗" end) [\(.index)] \(.action): \(.detail)"'
echo "--- accessibility tree ---"
echo "$result" | jq -r '.tree'
exit "$st"
