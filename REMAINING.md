# Remaining Features

Gaps identified in the v1 implementation relative to `BRIEF.md`. Ordered by user-visible impact.

---

## ~~1. Starter feed notifications (Feature 7)~~ — DONE

Wired `scheduleStarterFeedReminder` via `StarterViewModel.syncFeedReminder`, called from `StarterTab` `.task(id: nextFeed)` so it fires on appear and whenever the next-feed date changes. Upcoming bake's build-levain start time is now fed into the scheduler. `NotificationActionHandler` handles "Log Feed" and "Snooze 1h" actions; categories registered on app launch. Single stable identifier prevents stacking.

---

## 2. Fold notification deep-link to temperature entry (Notifications section)

**What's missing:** No `UNUserNotificationCenterDelegate`, no `didReceive` response handler, no `onOpenURL` anywhere in the codebase. Fold notifications fire but tapping one just opens the app to wherever it was last.

**Brief reference:** "Opening the notification deep-links to the temperature logging screen with the current fold pre-selected."

**What to do:**
- Implement a delegate that captures `UNNotificationResponse`, reads the fold's schedule-step ID from the notification `userInfo`, and routes the app to `TemperatureEntryView` pre-selected to that fold.
- Expose a navigation route on `ScheduleViewModel` (e.g. `pendingFoldEntry: ScheduleStep.ID?`) that the schedule tab observes and presents.
- Same mechanism applies to the "time to preheat" notification — it should open the active schedule.

---

## 3. Verify conflict-resolution option application (Feature 6)

**What to check:** `ConflictResolutionSheet` displays LLM-ranked options, but it's worth confirming end-to-end that tapping an option actually re-runs `ScheduleBuilder` with the chosen parameters (new bread-ready time, extended cold retard, swapped recipe) rather than just dismissing.

**Brief reference:** "The LLM returns options, the user taps one, the scheduler recalculates with the selected parameters."

**What to do:**
- Trace the `onSelect` / `apply` callback from `ConflictResolutionSheet` into `ScheduleViewModel`.
- Write a Swift Testing case that feeds a known conflict, accepts one option programmatically, and asserts the rebuilt schedule reflects the new parameters.
- If the apply path is absent or partial, wire it: each option needs enough structured payload (target time shift, cold-retard delta, recipe swap) to re-invoke the builder.

---

## 4. Per-ratio and per-temperature peak-time profiling (Feature 7)

**What's missing:** `StarterProfile` tracks a global average time-to-peak. The brief calls for bracketed averages so health assessment and levain-build estimates can be personalised to the user's actual feeding behaviour.

**Brief reference:** "It tracks average time-to-peak at different ratios and temperatures. This data can eventually feed back into the schedule builder to replace generic levain build estimates with personalised ones based on actual observations."

**What to do:**
- Bucket logged feeds by ratio (e.g. 1:1:1, 1:2:2, 1:5:5, 1:10:10) and temperature bracket (<22°C, 22–25°C, 26°C+).
- Store bracketed averages on `StarterProfile` as computed properties or a small derived struct.
- When the schedule builder encounters `build levain` and a matching bracket has ≥3 samples, prefer the observed average over the generic 4/5/6h default in `TemperatureCalculator`.

---

## 5. Liquid Glass morphing transition (Design section)

**What's missing:** No `GlassEffectContainer` or `glassEffectID` usage anywhere. Standard glass buttons and the system tab bar adopt Liquid Glass correctly, but the brief's specific morphing transition from recipe-selection into active schedule is not implemented.

**Brief reference:** "Use `GlassEffectContainer` and `glassEffectID` for the transition from recipe selection into the active schedule view. The selected recipe card morphs into the schedule header."

**What to do:**
- Wrap the recipe list and the schedule header in a shared `GlassEffectContainer`.
- Assign matching `glassEffectID` to the selected recipe card and the schedule header container so SwiftUI animates the morph.
- Verify with Reduce Transparency enabled — the fallback should be a cross-fade, not a broken transition.

---

## 6. Reduce Transparency fallback (Design — Accessibility)

**What to check:** The brief requires solid-slightly-translucent fallbacks when Reduce Transparency is on. No explicit `@Environment(\.accessibilityReduceTransparency)` reads appear in the codebase.

**What to do:**
- Audit all glass surfaces (action buttons, toolbar controls, any custom glass wrappers) and add a reduced-transparency branch that substitutes a solid material.
- Test with Dynamic Type at XXL to confirm glass elements don't clip or overlap text.

---

## Out of scope (confirmed, do not build in v1)

Custom recipe editor, multi-loaf planning, bake log/journal, photo capture, social, Watch companion, conversational LLM follow-up, HomeKit/weather temp, Bluetooth thermometer, iCloud sync. All correctly absent from the current build.
