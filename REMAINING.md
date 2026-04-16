# Remaining Features

Gaps identified in the v1 implementation relative to `BRIEF.md`. Ordered by user-visible impact.

---

## ~~1. Starter feed notifications (Feature 7)~~ — DONE

Wired `scheduleStarterFeedReminder` via `StarterViewModel.syncFeedReminder`, called from `StarterTab` `.task(id: nextFeed)` so it fires on appear and whenever the next-feed date changes. Upcoming bake's build-levain start time is now fed into the scheduler. `NotificationActionHandler` handles "Log Feed" and "Snooze 1h" actions; categories registered on app launch. Single stable identifier prevents stacking.

---

## ~~2. Fold notification deep-link to temperature entry (Notifications section)~~ — DONE

`NotificationActionHandler.didReceive` now routes `FOLD_STEP` default-action taps through `NotificationRouter` to `ScheduleViewModel.pendingFoldEntry`, which `ScheduleTab` observes as a sheet presenting `TemperatureEntryView` pre-selected to that fold. `COLD_RETARD_END` taps focus the Schedule tab via `NotificationRouter.selectedTab` bound on the root `TabView`.

---

## ~~3. Verify conflict-resolution option application (Feature 6)~~ — DONE

`ConflictOption` now carries an optional `targetTimeShiftMinutes` payload. `ScheduleViewModel.apply(option:availability:windows:)` shifts `targetDate` by that amount (when set) and re-invokes `buildPreview`, so the sheet's selection triggers a real rebuild instead of a silent dismiss. `ScheduleTab` wires the `ConflictResolutionSheet` `onOptionSelected` closure to that method. Covered by `ScheduleViewModelApplyOptionTests.applyingShiftedTargetOptionResolvesConflictAndRebuildsPreview`.

---

## ~~4. Per-ratio and per-temperature peak-time profiling (Feature 7)~~ — DONE

`StarterPeakProfile` in `Doug/Domain/Starter/` buckets feed logs by ratio (1:1:1, 1:2:2, 1:5:5, 1:10:10) and temperature bracket (<22°C, 22–25°C, 26°C+) and exposes `averageMinutes(ratio:tempBracket:)` (nil below 3 samples). `ScheduleBuilderInput` takes an optional `peakProfile`; `TemperatureCalculator.effectiveDuration` prefers the observed average for `buildLevain` at the standard 1:5:5 ratio when the matching bracket has ≥3 samples, falling back to the generic 4/5/6h estimate otherwise. `ScheduleTab` passes `feedLogs` through `ScheduleViewModel.buildPreview` and `apply` so the personalisation flows from SwiftData to the builder. Covered by `StarterPeakProfileTests` and `ScheduleBuilderPeakProfileTests`.

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
