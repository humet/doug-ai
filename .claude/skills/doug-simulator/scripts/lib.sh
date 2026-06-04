#!/usr/bin/env bash
# Shared helpers for the doug-simulator skill scripts.
# Source this from other scripts: `source "$(dirname "$0")/lib.sh"`
#
# Zero external dependencies beyond what ships with macOS + Xcode:
#   xcrun, simctl, sqlite3, sips, plutil  — all preinstalled.
#   jq is used opportunistically and degraded gracefully if absent.

set -euo pipefail

# --- Project constants (Doug-specific) -------------------------------------
# These are the only project-coupled values. If the project is renamed,
# update them here rather than across every script.
PROJECT="Doug.xcodeproj"
SCHEME="Doug"
APP_BUNDLE_ID="com.robfraserhumar.Doug"
UITEST_TARGET="DougUITests"

# Default simulator when none is booted. iPhone 17 Pro matches the device
# named in CLAUDE.md's build commands, keeping local + CI behaviour aligned.
DEFAULT_DEVICE="iPhone 17 Pro"

# --- Timeouts (seconds) ----------------------------------------------------
# Boot can be slow on a cold machine; 120s covers a first-boot from shutdown.
BOOT_TIMEOUT="${DOUG_SIM_BOOT_TIMEOUT:-120}"

# Resolve the skill root (parent of scripts/) so paths work from any cwd.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Walk up from the skill dir to the repo root (where Doug.xcodeproj lives).
REPO_ROOT="$(cd "$SKILL_DIR" && while [ ! -e "$PROJECT" ] && [ "$PWD" != "/" ]; do cd ..; done; pwd)"

die() { echo "error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Echo the UDID of the currently booted simulator. If none is booted, boot the
# default device and wait for it. Prints only the UDID on stdout.
booted_udid() {
  local udid
  udid="$(xcrun simctl list devices booted -j 2>/dev/null \
    | jq -r 'first(.devices[][].udid // empty)' 2>/dev/null || true)"
  if [ -z "$udid" ] || [ "$udid" = "null" ]; then
    echo "no booted simulator; booting '$DEFAULT_DEVICE'..." >&2
    udid="$(xcrun simctl list devices available -j \
      | jq -r --arg n "$DEFAULT_DEVICE" \
        'first(.devices[][] | select(.name==$n) | .udid)')"
    [ -n "$udid" ] && [ "$udid" != "null" ] || die "device '$DEFAULT_DEVICE' not found"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 &
    local waited=0
    until [ "$(xcrun simctl list devices -j | jq -r --arg u "$udid" \
      'first(.devices[][] | select(.udid==$u) | .state)')" = "Booted" ]; do
      sleep 1; waited=$((waited+1))
      [ "$waited" -lt "$BOOT_TIMEOUT" ] || die "boot timed out after ${BOOT_TIMEOUT}s"
    done
  fi
  printf '%s\n' "$udid"
}

# Echo the on-disk data container path for the installed app, or empty + nonzero
# if the app is not installed on the given simulator.
app_container() {
  local udid="$1"
  xcrun simctl get_app_container "$udid" "$APP_BUNDLE_ID" data 2>/dev/null
}
