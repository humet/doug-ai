#!/usr/bin/env bash
# Inspect Doug's persisted state on the booted simulator: the SwiftData store
# and UserDefaults. Reads live on-disk data — invaluable for debugging schedule
# / starter-feed state without adding logging.
#
# Usage:
#   state.sh tables                 # list SwiftData entity tables + row counts
#   state.sh dump <Table> [limit]   # rows from a table (default limit 20)
#   state.sh sql "<query>"          # run an arbitrary read-only SQL query
#   state.sh defaults               # dump app UserDefaults as JSON
#   state.sh path                   # print the resolved store + container paths
source "$(dirname "$0")/lib.sh"
udid="$(booted_udid)"
cmd="${1:-tables}"

container="$(app_container "$udid")" || die "Doug not installed on this simulator"

# SwiftData defaults to a store under Application Support. Glob rather than
# hardcode the filename so a renamed/custom store is still found.
store="$(find "$container/Library/Application Support" -name '*.store' -o -name '*.sqlite' 2>/dev/null | head -1)"

need_store() { [ -n "$store" ] && [ -f "$store" ] || die "no SwiftData store found (has the app run and saved data yet?)"; }

case "$cmd" in
  path)
    echo "container: $container"
    echo "store:     ${store:-<none yet>}" ;;
  tables)
    need_store
    # SwiftData prefixes entity tables with Z; show each with a row count.
    sqlite3 "file:$store?mode=ro" \
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' AND name NOT LIKE 'Z\_%' ESCAPE '\\';" \
      | while read -r t; do
          c="$(sqlite3 "file:$store?mode=ro" "SELECT count(*) FROM \"$t\";")"
          printf '%-32s %s rows\n' "$t" "$c"
        done ;;
  dump)
    need_store
    [ -n "${2:-}" ] || die "dump requires a table name (see: state.sh tables)"
    sqlite3 -header -column "file:$store?mode=ro" "SELECT * FROM \"$2\" LIMIT ${3:-20};" ;;
  sql)
    need_store
    [ -n "${2:-}" ] || die "sql requires a query string"
    # Opened read-only (mode=ro) so queries can never mutate the store.
    sqlite3 -header -column "file:$store?mode=ro" "$2" ;;
  defaults)
    plist="$container/Library/Preferences/$APP_BUNDLE_ID.plist"
    [ -f "$plist" ] || die "no preferences plist yet"
    plutil -convert json -o - "$plist" ;;
  *)
    die "unknown command '$cmd'" ;;
esac
