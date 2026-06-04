# Evaluation Scenarios

Run these after changing any script to confirm the skill still works. Each lists
the command, the gap it covers, and the expected behaviour. They use a booted
simulator with Doug installed (`scripts/app.sh state` → `installed`).

## Contents
- Eval 1: Inspect persisted starter-feed state
- Eval 2: Capture and read the current screen
- Eval 3: Drive a navigation flow and assert an element

## Eval 1: Inspect persisted starter-feed state

**Gap:** Reproduce/verify SwiftData state without adding logging or a debugger.

```bash
scripts/state.sh tables
scripts/state.sh dump ZSTARTERFEEDLOG 3
```

**Expected:**
- `tables` lists `Z`-prefixed entity tables (e.g. `ZSCHEDULE`, `ZSTARTERFEEDLOG`,
  `ZSTARTERPROFILE`) with non-negative row counts.
- `dump` prints a header + up to 3 rows. A write attempt (e.g.
  `state.sh sql "DELETE FROM ZSTARTERFEEDLOG"`) is rejected — the store is
  opened read-only.

## Eval 2: Capture and read the current screen

**Gap:** Confirm a UI change visually, cheaply.

```bash
scripts/shot.sh /tmp/eval-shot.png 400
```

**Expected:**
- Prints `✓ /tmp/eval-shot.png (400x...)`.
- The PNG is legible when read — the current tab, nav bar, and content are
  identifiable. A full-system firehose is NOT what's captured; it's Doug's UI.

## Eval 3: Drive a navigation flow and assert an element

**Gap:** Interact with the app (tap, assert) rather than only observe — the
capability that previously needed IDB.

```bash
scripts/drive.sh '[{"action":"tap","label":"Calculator"},
                   {"action":"wait","seconds":1},
                   {"action":"assertExists","label":"Calculator"},
                   {"action":"describe"}]'
```

**Expected:**
- Per-step output: `✓ [0] tap`, `✓ [2] assertExists`, `✓ [3] describe`.
- The accessibility tree shows Calculator-screen elements (e.g. `StaticText …
  label: 'Flour'`, a `TextField` with a numeric value).
- A deliberately wrong assertion (e.g. `assertExists` `label:"Nonexistent"`)
  yields `✗` for that step and a non-zero exit code.
