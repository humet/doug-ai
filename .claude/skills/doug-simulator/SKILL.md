---
name: doug-simulator
description: Build, run, inspect, and UI-drive the Doug iOS app on the simulator. Use when verifying a change in the running app, taking simulator screenshots, inspecting Doug's SwiftData store or UserDefaults, reproducing schedule/starter-feed state, testing dark mode / Dynamic Type / push notifications, or driving Doug's UI by accessibility label/identifier. Zero external dependencies — first-party xcrun/simctl/xcodebuild + XCUITest, no Python, no IDB.
---

# Doug Simulator

Verify Doug in the running app, not just in tests. Two layers:

- **Tier 1 — observe & control** (instant, zero deps): build, lifecycle, screenshots, SwiftData/UserDefaults inspection, device state, logs. Bash over `simctl`/`xcodebuild` + macOS built-ins (`sqlite3`, `sips`, `plutil`, `jq`).
- **Tier 2 — drive the UI** (slower, first-party): tap/type/swipe/assert by accessibility label or identifier via the XCUITest driver in `DougUITests/DougDriverUITests.swift`.

All scripts live in `scripts/` and auto-resolve the booted simulator (booting the default device if none is running). Run them directly.

## When to use which

| Goal | Use | Cost |
|---|---|---|
| Does it compile / do tests pass? | `build.sh` | slow |
| What's on screen right now? | `shot.sh` then read the PNG | instant |
| What's in the database? | `state.sh` | instant |
| Reproduce a UI state, tap through a flow | `drive.sh` | slow (builds + launches test runner) |
| Test dark mode / large text / a push | `device.sh` | instant |
| What did the app log? | `logs.sh` | ~seconds |

**Prefer `shot.sh` + reading the image for "how does it look"** — it's instant. Reserve `drive.sh` for when you must *interact* (tap a button, fill a field, assert an element exists after navigation). Put a whole flow in one `drive.sh` call; each call rebuilds and relaunches.

## Tier 1: observe & control

```bash
# Build / test (mirrors CLAUDE.md)
scripts/build.sh build            # build app for simulator
scripts/build.sh domain           # fast SPM domain tests (~0.15s)
scripts/build.sh test [Class]     # full xcodebuild test

# App lifecycle
scripts/app.sh install            # install latest build from DerivedData
scripts/app.sh launch             # launch
scripts/app.sh relaunch           # fresh process
scripts/app.sh open doug://...    # deep link
scripts/app.sh state              # installed / not-installed

# Screenshot (downscaled to 400px for token economy; pass a width or 0 for full)
scripts/shot.sh /tmp/doug.png 400

# Inspect persisted state (store opened READ-ONLY)
scripts/state.sh tables               # entity tables + row counts
scripts/state.sh dump ZSTARTERFEEDLOG # rows from a table
scripts/state.sh sql "SELECT ..."     # arbitrary read-only query
scripts/state.sh defaults             # UserDefaults as JSON
scripts/state.sh path                 # store + container paths

# Device conditions
scripts/device.sh appearance dark
scripts/device.sh content-size accessibility3
scripts/device.sh push "Levain ready" "Time to bake"
scripts/device.sh statusbar-clean     # 9:41, full battery — for clean shots

# Logs (scoped to the Doug process)
scripts/logs.sh tail 8
scripts/logs.sh errors 8
```

SwiftData entity tables are SQLite tables prefixed with `Z` (e.g. `ZSCHEDULE`, `ZSTARTERFEEDLOG`). Column names are uppercased and `Z`-prefixed (`ZTIMESTAMP`, `ZFLOURTYPE`). Use `state.sh tables` to discover them, then `dump`/`sql`.

## Tier 2: drive the UI

```bash
# Inline steps
scripts/drive.sh '[{"action":"tap","label":"Feed & Refrigerate"},
                   {"action":"assertExists","label":"Levain"},
                   {"action":"describe"}]'

# Or from a file
scripts/drive.sh -f flow.json
```

Output is per-step `✓`/`✗` plus the resulting accessibility tree. Steps resolve elements by `id` (accessibility identifier) or `label` (visible text). The full step schema and how to add accessibility identifiers to Doug's SwiftUI views are in **[reference/xcuitest-driver.md](reference/xcuitest-driver.md)**.

## Verifying a change — workflow

```
- [ ] 1. Build:        scripts/build.sh build
- [ ] 2. Install+launch: scripts/app.sh install && scripts/app.sh launch
- [ ] 3. Look:         scripts/shot.sh /tmp/doug.png  (then read the PNG)
- [ ] 4. Interact:     scripts/drive.sh '[...]'  (only if a flow needs driving)
- [ ] 5. Confirm data: scripts/state.sh dump ZSTARTERFEEDLOG
```

Evaluation scenarios for this skill are in **[reference/evals.md](reference/evals.md)** — run them after changing any script.

## Requirements

macOS + Xcode (provides `xcrun`, `simctl`, `xcodebuild`, `sqlite3`, `sips`, `plutil`). `jq` is used for JSON. No Python, no IDB.
