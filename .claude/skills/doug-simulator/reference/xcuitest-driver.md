# XCUITest Driver Reference

The Tier 2 driver lives in `DougUITests/DougDriverUITests.swift` and is invoked
by `scripts/drive.sh`. It executes a JSON step list in a single app launch and
emits a structured result (per-step status + accessibility tree) that the script
parses.

## Contents
- Step schema
- How element resolution works
- Adding accessibility identifiers to Doug's views
- How steps reach the test (TEST_RUNNER_ env forwarding)
- Limitations

## Step schema

A step list is a JSON array. Each step is an object with an `action`:

| action | fields | effect |
|---|---|---|
| `tap` | `id` or `label` | tap the first matching element |
| `typeText` | `id`/`label`, `text` | tap the field, then type `text` |
| `swipe` | `direction`: up/down/left/right | swipe the whole app view |
| `wait` | `seconds` (number) | sleep |
| `assertExists` | `id` or `label` | step fails if element not found within 5s |
| `describe` | — | snapshot the accessibility tree (always emitted at end too) |

Example flow file (`flow.json`):
```json
[
  {"action":"assertExists","label":"Ready to Bake!"},
  {"action":"tap","label":"Feed & Refrigerate"},
  {"action":"wait","seconds":1},
  {"action":"assertExists","label":"Fridge"},
  {"action":"describe"}
]
```

Run: `scripts/drive.sh -f flow.json`

## How element resolution works

- **`id`** → `app.descendants(matching: .any).matching(identifier: id)` — matches
  any element type carrying that accessibility identifier. Most robust; survives
  copy changes.
- **`label`** → matches any element whose accessibility `label` equals the string
  exactly. Convenient (no code changes) but brittle to wording/localization.

Prefer `id` for elements you drive repeatedly; use `label` for one-off checks.

## Adding accessibility identifiers to Doug's views

Add identifiers in the SwiftUI layer so flows are stable:

```swift
Button("Feed & Refrigerate") { … }
    .accessibilityIdentifier("feedAndRefrigerateButton")
```

Then drive by id: `{"action":"tap","id":"feedAndRefrigerateButton"}`.

Identifiers are invisible to users and do not change layout — safe to add freely
on interactive controls (buttons, fields, key rows) you want to automate.

## How steps reach the test

`xcodebuild` forwards any environment variable prefixed `TEST_RUNNER_` to the
test runner process with the prefix stripped. `drive.sh` sets
`TEST_RUNNER_DOUG_DRIVER_STEPS`, and the test reads
`ProcessInfo.processInfo.environment["DOUG_DRIVER_STEPS"]`. To launch the app
with launch arguments, set `DOUG_DRIVER_LAUNCH_ARGS` (space-separated) the same
way.

## Limitations

- Each `drive.sh` call incrementally builds and launches a test runner
  (seconds to minutes). Batch a whole flow into one call.
- `label` matching is exact and case-sensitive.
- The accessibility tree is truncated at 6000 chars (constant `treeCharLimit`
  in the driver) to bound log size; raise it there if a screen is deeper.
- `continueAfterFailure` is `true` so all steps run and report, but the overall
  test (and `drive.sh` exit code) is non-zero if any step failed.
