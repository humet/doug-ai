#!/usr/bin/env bash
# Manage Doug's lifecycle on the booted simulator.
#
# Usage:
#   app.sh install [path.app]   # install a built .app (auto-finds latest if omitted)
#   app.sh launch               # launch the app
#   app.sh relaunch             # terminate then launch (fresh process)
#   app.sh terminate            # terminate the app
#   app.sh open <url>           # open a deep link (e.g. doug://schedule)
#   app.sh state                # installed / running / not-installed
source "$(dirname "$0")/lib.sh"
udid="$(booted_udid)"
cmd="${1:-launch}"

# Locate the most recently built Doug.app in DerivedData for this scheme.
find_app() {
  local dd="$HOME/Library/Developer/Xcode/DerivedData"
  find "$dd" -type d -name "Doug.app" -path "*Debug-iphonesimulator*" \
    -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

case "$cmd" in
  install)
    app="${2:-$(find_app)}"
    [ -n "$app" ] && [ -d "$app" ] || die "no .app found; run build.sh build first"
    xcrun simctl install "$udid" "$app" && echo "✓ installed $(basename "$app")" ;;
  launch)
    xcrun simctl launch "$udid" "$APP_BUNDLE_ID" >/dev/null && echo "✓ launched" ;;
  relaunch)
    xcrun simctl terminate "$udid" "$APP_BUNDLE_ID" 2>/dev/null || true
    sleep 1
    xcrun simctl launch "$udid" "$APP_BUNDLE_ID" >/dev/null && echo "✓ relaunched" ;;
  terminate)
    xcrun simctl terminate "$udid" "$APP_BUNDLE_ID" 2>/dev/null && echo "✓ terminated" \
      || echo "not running" ;;
  open)
    [ -n "${2:-}" ] || die "open requires a url"
    xcrun simctl openurl "$udid" "$2" && echo "✓ opened $2" ;;
  state)
    if app_container "$udid" >/dev/null 2>&1; then echo "installed"; else echo "not-installed"; fi ;;
  *)
    die "unknown command '$cmd'" ;;
esac
