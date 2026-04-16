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

## ~~5. Liquid Glass morphing transition (Design section)~~ — DONE

Added a shared `@Namespace` (`glassNamespace`) on `ScheduleTab` and wrapped the recipe-selection / active-header branch in a `GlassEffectContainer`. The selected `RecipeCard` applies `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))` with `glassEffectID("selectedRecipe", …)`; the active bake header applies the non-interactive variant of the same effect and ID, so SwiftUI morphs between them. Flipping `activeSchedule` is now wrapped in `withAnimation(.smooth)` inside the `ScheduleConfigSheet` completion so the transition animates. `@Environment(\.accessibilityReduceTransparency)` gates the container and the glass modifiers: when on, the morph region skips `GlassEffectContainer` and both participants fall back to `.ultraThinMaterial` in the same rect shape, letting the default `.opacity` transition cross-fade the branches. Active bake chart, "Adjust Cold Retard" button, and step timeline sit outside the morph region and are untouched.

---

## ~~6. Reduce Transparency fallback (Design — Accessibility)~~ — DONE

Extracted `adaptiveGlassButtonStyle(prominent:)` in `Doug/Views/Components/AdaptiveGlassButtonStyle.swift`. The modifier reads `@Environment(\.accessibilityReduceTransparency)` and swaps `.glass`/`.glassProminent` for `.bordered`/`.borderedProminent` when on. Wired into "Plan Bake" and "Adjust Cold Retard" in `ScheduleTab` and the `GlassActionButton` component. The three `.glassEffect`/`GlassEffectContainer` sites on the morph region already had sibling fallbacks from item #5 (morph skips the container and both branches fall back to `.ultraThinMaterial`). Dynamic Type at XXL spot-check still needs a manual run on the simulator — previews render without clipping but the `.bordered` style wraps differently than glass in constrained widths, so it's worth eyeballing.

---

## Out of scope (confirmed, do not build in v1)

Custom recipe editor, multi-loaf planning, bake log/journal, photo capture, social, Watch companion, conversational LLM follow-up, HomeKit/weather temp, Bluetooth thermometer, iCloud sync. All correctly absent from the current build.
