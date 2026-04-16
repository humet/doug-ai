# Sourdough Companion — Feature Brief

## Overview

A native iOS app that helps regular sourdough bakers fit the multi-day baking process around their real life. The core problem isn't technique — it's scheduling. The app works backwards from "I want bread ready by Saturday 9am" and builds a step-by-step timeline that respects when you're unavailable, adjusts for your kitchen temperature, and uses an LLM to explain tradeoffs when the schedule can't fit.

## Target User

Someone who bakes sourdough regularly and understands the process, but finds the timing logistics frustrating. They don't need to be told what autolyse means — they need to know when to start it, given that they have a school run at 8:15 and gym at 6pm.

## Platform & Stack

- **Native iOS** — SwiftUI, targeting iOS 26+
- **Design language** — Apple Liquid Glass (see Design section)
- **Local data** — SwiftData for starter logs, recipes, unavailability windows, schedule history
- **LLM integration** — Anthropic Claude API for schedule conflict resolution (online-only feature)
- **Single loaf** — All recipes and calculations assume one loaf. No multi-bake planner.

---

## Features

### 1. Built-in Recipes

Four recipes ship with v1. Each recipe defines two things: its ingredients and its method. The method is an ordered sequence of steps — the schedule builder consumes this sequence directly and is agnostic to what the steps are. This means future recipes can introduce different methods (same-day bakes with no cold retard, no-fold long bulk ferments, enriched doughs with lamination, pizza with a completely different shaping and bake) without changing the scheduler.

**Step vocabulary:**

Recipes compose their methods from a shared set of step types. Each step type defines a label, a classification (hands-on, passive-flexible, or passive-fixed), a default duration, whether the duration is temperature-adjusted, any flex range, and whether the step requires a dough temperature reading. The `requiresTempReading` flag is a property of the step template — any step type can carry it, and the scheduler and notification system handle it generically. The v1 step types are:

- **Build levain** — Passive (fixed). Initial feed is a brief hands-on moment; the rest is waiting. Duration is temperature-adjusted.
- **Autolyse** — Passive (flexible). Duration range: 30–60 min.
- **Mix** — Hands-on. Fixed 5 min. Requires temp reading (initial dough temperature baseline).
- **Bulk ferment** — Passive (fixed). Duration is temperature-adjusted. Contains a sub-sequence of stretch & fold steps.
- **Stretch & fold** — Hands-on. Fixed 2–3 min each. Scheduled within the bulk ferment window. Requires temp reading.
- **Add inclusions** — Hands-on. Fixed 2 min. Optional step within bulk ferment for recipes with mix-ins, triggered at a specific fold number.
- **Shape** — Hands-on. Fixed 20 min (includes pre-shape and bench rest).
- **Cold retard** — Passive (flexible). Duration range defined per recipe.
- **Preheat** — Passive (fixed). Fixed 60 min.
- **Bake covered** — Passive (fixed). Duration defined per recipe.
- **Bake uncovered** — Passive (fixed). Duration defined per recipe.

This vocabulary covers all v1 recipes and is extensible. Future step types (e.g. "warm proof", "lamination", "ball and oil") can be added without modifying the scheduler — only the step classification and duration rules need to be defined.

**Recipes:**

**Country Loaf** — The standard. 70% hydration, white bread flour, mild tang, open crumb. The recipe most users will start with. Method: build levain → autolyse → mix → bulk ferment (4 folds) → shape → cold retard (8–18h) → preheat → bake covered → bake uncovered.

**High Hydration Artisan** — 80% hydration. Lacier crumb, more extensible dough, requires more confident handling. Longer bulk ferment and cold retard than the country loaf. Method: same step sequence as country loaf, with 5 folds and longer durations.

**Whole Wheat & Honey** — 40% whole wheat flour, 68% hydration, with 30g honey. Denser crumb, slightly sweet, great for toast. Shorter bulk ferment due to whole wheat enzyme activity. Higher levain proportion (125g vs 100g) to compensate for the bran cutting gluten strands. Method: same step sequence as country loaf, with 3 folds.

**Olive & Rosemary** — 10% whole wheat, 69% hydration, with 80g halved olives and fresh rosemary. Savoury, pairs well with soup and cheese. Method: same step sequence as country loaf, with an "add inclusions" step at fold 2.

Each recipe displays its ingredients, a brief description, and the key parameters (hydration, approximate total time, difficulty) so the user can pick quickly. Recipes are read-only in v1 — no custom recipe editor.

Note: the four v1 recipes happen to share the same core method with minor variations. The architecture supports fundamentally different methods, but the v1 recipe set intentionally keeps things familiar.

### 2. Schedule Builder

The primary feature. The user selects a recipe and sets a target time for when they want finished bread. The scheduler reads the recipe's method — an ordered sequence of steps — and works backwards from the target time to produce a timeline.

**How the scheduler works:**

The scheduler iterates through the recipe's step sequence in reverse order, allocating time for each step based on its duration, classification, and parameters. It doesn't know or care what the steps are called — it only needs each step's classification and duration rules. This makes the scheduler reusable across any recipe method without modification.

For each step, the scheduler:
1. Subtracts the step's duration from the current time cursor.
2. If the step is hands-on, checks whether it overlaps any unavailable window. If it does, attempts to resolve the conflict by adjusting adjacent flexible steps or shifting the step within its allowed range.
3. If the step's duration is temperature-adjusted, applies the kitchen temperature correction before placing it.
4. If the step contains sub-steps (e.g. folds within bulk ferment), schedules those within the parent step's window.

**Step classification:**

Each step in the recipe's method carries one of three classifications, which drives how the scheduler handles conflicts:

- **Hands-on** — Must not overlap with unavailable windows. Examples: mix, each individual stretch & fold, shape, scoring/loading the bake, adding inclusions.
- **Passive (flexible duration)** — Can run through unavailable windows. Duration can stretch or compress within a defined range. Examples: autolyse, cold retard.
- **Passive (fixed duration)** — Can run through unavailable windows but duration is fixed (or temperature-derived). Examples: bulk ferment, levain build, preheat, bake.

**Stretch & fold sub-scheduling:**

When the scheduler encounters a bulk ferment step that contains fold sub-steps, it schedules the individual folds within the bulk window. Folds are evenly spaced across the first 60–75% of the bulk ferment. Each fold is a brief hands-on moment (2–3 minutes). The scheduler tries to avoid placing folds inside unavailable windows. If a fold would land during an unavailable block, it shifts the fold earlier or later within an acceptable range (up to ±15 minutes) without changing the overall bulk duration.

### 3. Availability & Scheduling Constraints

The scheduler respects a hierarchy of constraints that define when the user can and can't do hands-on baking steps.

**Daily available hours** — The outer boundary. The user sets the window during which they're available for hands-on steps — for example, 6:30am to 9:00pm. Anything outside this window is treated the same as sleep: no hands-on steps will be scheduled there. This is set once during onboarding and adjustable in settings. Passive steps (autolyse, cold retard, bulk ferment between folds) can run through the night and outside available hours without restriction.

**Unavailable windows (within available hours)** — Recurring and one-off blocks that carve out time within the daily available window.

- **Recurring windows** — Repeat weekly. Examples: school run Mon–Fri 8:15–9:00, gym Tue/Thu 6:00–7:15pm, work hours Mon–Fri 9:00–5:30.
- **One-off windows** — Single blocks for specific dates. Example: dentist appointment Thursday 2–3pm.

**Constraint hierarchy:**

1. Daily available hours — the outer boundary. Nothing hands-on outside this.
2. Unavailable windows — blocks within available hours where hands-on steps can't be placed.
3. Passive steps run through everything — nights, unavailable windows, whenever.

The schedule builder, feed scheduler, and revival plan all respect this same constraint hierarchy. The UI for managing these should be simple — available hours as a time range picker in settings, unavailable windows as a list of named blocks with day/time, easy to add, edit, and delete.

### 4. Temperature-Aware Timing

Kitchen temperature is used to generate the initial schedule estimate. It affects two durations:

**Bulk ferment** — Each recipe defines a base duration at a reference temperature (24°C). The app applies an exponential adjustment: roughly 7% shorter per degree above reference, 7% longer per degree below. At 20°C, a 4-hour bulk becomes approximately 5 hours. At 28°C, it drops to around 3 hours. This estimate sets the initial schedule, but once the bake is active, degree-hour tracking (see feature 9) takes over as the real-time correction.

**Levain build** — Warmer kitchens mean faster levain peak. The app estimates 4 hours at 26°C+, 5 hours at 22–25°C, 6 hours below 22°C. Once the starter tracker has enough data, these estimates can be replaced with the user's actual observed peak times.

The user sets their kitchen temperature via a simple slider or stepper (16–32°C range). The schedule updates in real-time as they adjust. A future enhancement could pull ambient temperature from HomeKit or a weather API, but v1 is manual input.

### 5. Cold Retard Flexibility

The cold retard step is the primary shock absorber in the schedule. Each recipe defines a minimum and maximum cold retard duration. The country loaf, for example, allows 8–18 hours.

**"Life Happened" adjustment** — At any point after shaping, the user can adjust the cold retard duration within the allowed range. The app recalculates all downstream steps (preheat time, bake time, bread-ready time) and updates the schedule and notifications.

**UI** — A slider showing the current cold retard duration within the allowed range, with the downstream impact shown in real-time. Moving the slider later pushes bread-ready later. The app should note flavour impact: longer cold retards develop more sour flavour, shorter retards are milder.

### 6. Schedule Conflict Resolution (LLM)

When the mechanical scheduler cannot fit all hands-on steps around the user's unavailable windows for the requested bread-ready time, it hands off to Claude.

**Trigger** — The scheduler fails to produce a valid timeline. It packages the conflict details as structured data: which step conflicted with which unavailable window, what the flexibility ranges are for adjustable steps, and what the nearest valid bread-ready times are.

**LLM prompt** — Claude receives the conflict data plus the recipe context and responds with 2–3 ranked options, each explained in plain English with baking-relevant tradeoffs. Examples:

- "Bake an hour later at 10am — everything fits without changes."
- "Extend the cold retard to 16 hours and shape the night before at 9:30pm instead of the morning. The longer retard will give you a tangier crumb, which works well with the country loaf."
- "Switch to the whole wheat recipe — its shorter bulk ferment clears your afternoon window."

**Interaction model** — One-shot. The LLM returns options, the user taps one, the scheduler recalculates with the selected parameters. No conversational follow-up in v1.

**Offline behaviour** — If the device is offline when a conflict occurs, the app falls back to showing the raw options without natural-language explanations: "Bake at 10am instead" / "Shape at 9:30pm, retard 16h" / "No valid schedule for this recipe today."

**Token efficiency** — The prompt should be tightly structured. The LLM doesn't need the full recipe — just the conflict details, flex ranges, and enough context to explain tradeoffs. Target: single API call, response under 300 tokens.

### 7. Starter Feed Tracker

A dedicated section for logging and understanding your starter's behaviour over time.

**Feed logging** — Each feed records: date/time, feed ratio (e.g., 1:5:5 meaning 1 part starter, 5 parts flour, 5 parts water), flour type used, and kitchen temperature at time of feeding.

**Peak tracking** — After logging a feed, the user can mark when the starter peaked (hit maximum rise). The app calculates time-to-peak for each feed and stores it.

**Starter profile** — Over time, the app builds a model of the starter's behaviour. It tracks average time-to-peak at different ratios and temperatures. This data can eventually feed back into the schedule builder to replace generic levain build estimates with personalised ones based on actual observations.

**Feed scheduler** — Rather than a simple "you haven't fed in X days" timer, the app suggests specific times to feed. It considers:

- The user's configured maintenance cycle (default: every 5–7 days for fridge-stored, daily for counter-stored).
- The user's unavailable windows — it won't suggest feeding during the school run or gym.
- Upcoming planned bakes — if a bake is scheduled for Saturday, the app works backwards from the levain build time and suggests a maintenance feed that ensures the starter is active and healthy when needed. For example: "Feed your starter Wednesday at 7pm — that keeps it on a healthy cycle and lines it up well for your Saturday bake."
- If no bake is planned, the app maintains a steady rhythm based on the configured cycle, suggesting the next feed at a convenient time that avoids unavailable windows.

Feed suggestions appear as a notification at the suggested time and as a persistent "next feed" card on the starter screen. The user can dismiss, snooze, or log the feed directly from the notification.

**Starter health assessment** — The app continuously evaluates starter health based on two signals: time since last feed and recent time-to-peak trend. It assigns one of three statuses:

- **Ready to bake** — Fed within a reasonable window and recent peak times are within the user's historical average.
- **Needs a feed first** — Last feed was moderately overdue (e.g. 7–10 days for fridge-stored) but recent peak times were normal. A single feed and wait-for-peak should be sufficient before building a levain.
- **Needs revival** — Last feed was significantly overdue (e.g. 10+ days for fridge-stored, 48+ hours for counter-stored), or recent time-to-peak readings have been trending significantly slower than the user's historical average. The starter is likely sluggish and needs multiple consecutive feeds before it's reliable enough to bake with.

The thresholds for each status are configurable and refine over time based on the user's logged data. If a user's starter reliably peaks at 5 hours even after 12 days in the fridge, the app learns that and adjusts the assessment accordingly.

**Pre-bake health check** — When the user taps "Start Bake," the app checks the starter's current status before generating a schedule. If the status is "ready to bake," the schedule is generated normally. If the status is "needs a feed first," the app adds a single feed-and-wait step to the beginning of the schedule and adjusts the total timeline. If the status is "needs revival," the app blocks the schedule and directs the user to the revival plan, showing the earliest realistic bake time once the starter is restored.

**Revival plan** — A guided feeding schedule to bring a neglected starter back to strength. The app generates a sequence of 2–3 consecutive feeds at room temperature, typically at a tight ratio like 1:2:2, spaced based on expected peak times. Each revival feed is a tracked step with a notification. The user logs time-to-peak at each feed as usual. The app monitors the trend — once peak time drops back to within range of the user's historical average (or within a sensible default for new users), it clears the starter as bake-ready and the user can proceed to schedule a bake.

**Display** — A timeline view showing recent feeds, with each entry showing the ratio, time-to-peak (if recorded), and temperature. A summary card at the top shows: last fed (time ago), average time to peak at the most-used ratio, current health status with a clear indicator (ready / needs feed / needs revival), next suggested feed time (with context — e.g. "Wednesday 7pm — keeps you on track for Saturday bake"), and — if in revival — progress through the revival plan with estimated time until bake-ready.

### 8. Hydration & Formula Calculator

A standalone tool for calculating true hydration and scaling recipes.

**True hydration calculator** — Accounts for the flour and water in the levain, not just the main dough. For a 100% hydration levain, the levain contributes equal parts flour and water. The calculator shows both the "dough hydration" (just flour + water) and the "total hydration" (including levain contribution).

**Inputs** — Flour weight, water weight, levain weight, levain hydration percentage, salt weight. Optional: percentage of whole wheat or other flours.

**Scaling** — The user can adjust the total dough weight and all ingredients scale proportionally. Useful for adjusting from the built-in recipe amounts.

**Output** — Total dough weight, true hydration percentage, flour breakdown (if multiple flours), baker's percentages for all ingredients.

### 9. Dough Temperature Tracking & Degree-Hours

The core mechanism for determining bulk ferment readiness. Rather than relying solely on elapsed time, the app tracks accumulated degree-hours — a measure of total fermentation energy — using the dough temperature readings the user logs at each stretch & fold.

**How degree-hours work:**

Fermentation progress is roughly proportional to dough temperature integrated over time. The app sums (dough temp minus a base temperature) × time for each interval between readings. The base temperature is approximately 4°C, below which yeast activity is negligible. Each recipe defines a target degree-hour threshold that represents a complete bulk ferment — for example, the country loaf at 24°C for 4 hours accumulates roughly 80 degree-hours above base.

The app interpolates between the discrete readings at each fold to estimate a continuous temperature curve, then calculates the running total against the recipe's target threshold.

**User experience:**

The user takes a reading with a probe thermometer at each stretch & fold and logs it in the app. Since they're already handling the dough at each fold, this adds no extra friction — just a number entry. The app shows:

- A simple temperature curve across the bulk ferment, with each fold as a data point.
- A progress bar or percentage showing accumulated degree-hours against the recipe's target threshold.
- An estimated time remaining to reach the threshold, updated after each reading.
- A notification when the threshold is approaching: "Bulk ferment is nearly done — check your dough in ~20 minutes."

**Initial mix temperature** — The user logs the dough temperature immediately after mixing. This is the first data point and the starting baseline. The app can also display the theoretical desired dough temperature (a function of flour, water, levain, and ambient temps) as a reference.

**Self-correcting schedule:** If fermentation is running ahead of schedule (warmer dough, faster accumulation), the app adjusts the estimated bulk end time earlier and pushes downstream steps (shape, cold retard, bake) forward. If fermentation is running behind (cooler dough, slow accumulation), it extends bulk and pushes everything back. Updated times trigger updated notifications. This integrates directly with the schedule builder.

**Learning over time:** Each bake's degree-hour total is stored alongside the recipe, kitchen temp, starter feed data, and — eventually — a subjective outcome note (good crumb, under-proofed, over-proofed). Over multiple bakes, the app refines the target degree-hour threshold per recipe based on actual results. If the user consistently gets good results at 85 degree-hours rather than the default 80, the threshold adjusts. This replaces the generic exponential time adjustment with a personalised model calibrated to the user's specific starter, flour, and environment.

**Relationship to kitchen temperature:** Kitchen temperature (feature 4) generates the initial schedule estimate before the bake starts. Degree-hours provide real-time correction during the bake using actual dough data. Kitchen temp is the prediction; degree-hours are the ground truth.

**Aliquot jar (optional manual override):** For users who prefer a visual volume-based check, the app supports an optional aliquot jar mode. The user pulls a small piece of dough at mix time into a straight-sided jar and logs estimated rise percentage at each fold alongside the temperature. This is not the primary mechanism — degree-hours drive the schedule — but it provides a secondary data point for users who want it. The rise percentage is stored in the bake log and can be displayed alongside the degree-hour curve.

---

## Design — Liquid Glass

The app targets iOS 26 and should use Apple's Liquid Glass design language intentionally — on the navigation layer only, never on content.

### Where to use glass

**Tab bar** — The primary navigation between Schedule, Starter, and Calculator tabs. This adopts glass automatically when compiling with Xcode 26 and using the standard TabView.

**Floating action buttons** — "Start Bake" on the recipe selection screen, "Life Happened" adjustment button floating over an active schedule. These are interactive controls floating above content — ideal for `.glassEffect(.regular.interactive())`.

**Toolbar controls** — The temperature slider, recipe picker, and cold retard adjustment controls. These float above the schedule content as a navigation/control layer.

**Morphing transitions** — Use `GlassEffectContainer` and `glassEffectID` for the transition from recipe selection into the active schedule view. The selected recipe card morphs into the schedule header.

### Where to hold back

**Schedule timeline** — This is content. Steps, times, durations, and status indicators should sit on solid, high-contrast surfaces. No glass on the timeline cards.

**Starter feed log** — Data entries in a list. Solid backgrounds, clear typography, no glass.

**Calculator inputs and results** — Functional content. Solid surfaces, readable numbers.

**Avoid stacking glass** — Never layer a glass card inside a glass sheet above a glass tab bar. Maximum one glass surface visible above the content at any time (excluding the tab bar, which is system-level).

### Background considerations

The content behind glass matters. A warm, muted background (think parchment, warm cream, soft wheat tones) will look good through glass and maintain contrast. Avoid busy textures or photography as full backgrounds — they degrade legibility through glass layers.

### Accessibility

Respect the Reduce Transparency setting. When enabled, glass surfaces should fall back to solid, slightly translucent backgrounds. All text must remain on solid layers, never placed directly on glass. Test with Dynamic Type at larger sizes to ensure glass elements don't clip or overlap text.

---

## Notifications

The app uses local notifications to alert the user to upcoming hands-on steps.

**Timing** — Notifications fire 5 minutes before each hands-on step (feed levain, mix, each fold, shape, preheat, score & bake).

**Content** — Each notification includes the step name, what to do, and the next step after this one. Example: "Time to shape — Pre-shape your dough, bench rest 15 min, then final shape into banneton. Next: into the fridge for 12h cold retard."

**Fold notifications** — Fold step notifications include a prompt to log dough temperature: "Fold 2 of 4 — Stretch & fold, then take a dough temp reading. Current rise: +0.8°C from mix." Opening the notification deep-links to the temperature logging screen with the current fold pre-selected.

**Passive steps** — No notification for the start of passive steps (autolyse, cold retard, bulk ferment between folds). The schedule view shows these, but they don't interrupt the user.

**Cold retard end** — A notification fires when the cold retard is ending: "Time to preheat — Pull your dough from the fridge and get the dutch oven in at [temp]°C."

---

## Data Model (Conceptual)

**Recipe** — Name, description, ingredients (flour, water, salt, levain weight, levain hydration), extras (optional), method (ordered array of Method Steps), bake temperature, difficulty rating.

**Method Step (template)** — Step type (from the step vocabulary), label, classification (hands-on / passive-flexible / passive-fixed), base duration, temperature-adjusted flag, reference temperature (if temp-adjusted), flex range min/max (if flexible), fold count (if bulk ferment), degree-hour target threshold (if bulk ferment — used by real-time tracking to determine readiness), sub-steps (if applicable, e.g. add-inclusions at a specific fold), notification text template, user-facing instruction text.

**User Availability** — Daily available hours start time, daily available hours end time. Set during onboarding, adjustable in settings. Respected by the schedule builder, feed scheduler, and revival plan.

**Unavailable Window** — Name, days of week (for recurring), start time, end time (must fall within daily available hours), specific date (for one-off), active flag.

**Schedule** — Reference to recipe, target bread-ready time, kitchen temperature, generated step list (instantiated from the recipe's method), status (planning / active / complete).

**Schedule Step (instance)** — Reference to method step template, computed start time, computed duration (after temperature adjustment and flex), status (upcoming / active / done / skipped), notification identifier.

**Dough Temperature Reading** — Reference to schedule, timestamp, temperature (°C), associated step (typically a fold), sequence number within the bulk ferment, accumulated degree-hours at time of reading (computed).

**Bake Fermentation Profile** — Derived/computed per completed bake: initial mix temp, readings at each fold, final accumulated degree-hours, target degree-hour threshold used, associated recipe, kitchen temp, aliquot jar rise percentage at each fold (nullable), subjective outcome note (nullable — e.g. "good crumb", "slightly under-proofed"). Used to refine per-recipe degree-hour thresholds over time.

**Starter Feed Log** — Timestamp, ratio (starter:flour:water), flour type, kitchen temperature, peak timestamp (nullable), computed time-to-peak (nullable).

**Starter Profile** — Derived/computed: average time-to-peak by ratio bracket and temperature bracket, current health status (ready / needs-feed / needs-revival), storage type (fridge / counter), maintenance cycle interval (configurable, default 5–7 days fridge / 24h counter), next suggested feed time (computed from cycle, unavailable windows, and upcoming bakes), health assessment thresholds (configurable, refined over time based on user data). Rebuilt on each new log entry.

**Revival Plan** — Reference to starter profile, generated feed sequence (array of planned feeds with target ratio, expected time-to-peak, notification identifiers), status (active / completed / cancelled), start date, target bake-ready date (estimated).

---

## Out of Scope for V1

- Custom recipe creation or editing
- Multiple loaf / batch planning
- Bake log / journal
- Photo capture
- Social sharing
- Apple Watch companion
- Conversational LLM follow-up (conflict resolution is one-shot only)
- HomeKit / weather API temperature integration
- Bluetooth thermometer integration (e.g. Combustion Inc.) for continuous dough temperature monitoring — v1 uses manual readings at fold times
- iCloud sync