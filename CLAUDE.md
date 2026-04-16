# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Build & Run

```bash
# Build for simulator
xcodebuild -project Doug.xcodeproj -scheme Doug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests (Swift Testing for unit, XCTest for UI)
xcodebuild -project Doug.xcodeproj -scheme Doug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Open in Xcode (Cmd+R to run)
open Doug.xcodeproj
```

No external package dependencies. Zero SPM, CocoaPods, or Carthage.

When the Xcode MCP server is connected, prefer it over `xcodebuild` CLI for building, previewing, and inspecting issues. Key tools: `BuildProject`, `RenderPreview`, `XcodeListNavigatorIssues`.

## Lint & Format

```bash
swiftlint lint
swiftformat Doug/
swiftformat --lint Doug/
```

Config files: `.swiftlint.yml` and `.swiftformat` in the project root.

## Architecture

MVVM + Domain Services. Five layers under `Doug/`:

- **Models/SwiftData/** — `@Model` types for persistence (Schedule, ScheduleStep, StarterFeedLog, UserAvailability, etc.)
- **Models/Static/** — Plain Swift structs and enums for recipes and step types (not persisted — read-only data compiled into the app)
- **Domain/** — Pure Swift business logic. **No SwiftUI or SwiftData imports.** Contains the schedule builder algorithm, temperature calculations, degree-hour tracking, hydration calculator, and starter health assessment. All independently testable without a simulator.
- **ViewModels/** — `@Observable` `@MainActor` state managers bridging Domain and Views. Injected via `.environment()`.
- **Views/** — SwiftUI views organized by tab (Schedule, Starter, Calculator) plus Components, Settings, and Onboarding.
- **Services/** — External integrations (Anthropic Claude API, local notifications).
- **Theme/** — Colors, typography constants.

## Data Flow

1. `DougApp` creates the SwiftData `ModelContainer` and injects ViewModels via `.environment()`
2. ViewModels hold references to `ModelContext` for CRUD operations
3. Domain logic is called by ViewModels as pure functions — e.g. `ScheduleBuilder.build(input:)`
4. Results are written back to SwiftData models and trigger view updates via `@Observable`

## Key Patterns

- **Swift 6 concurrency**: async/await, actors for services, `@MainActor` for ViewModels and `@Observable` classes
- **`@Observable` (iOS 17+)**: All ViewModels use `@Observable`, not `ObservableObject`. Use `@State` for view-owned instances, `@Bindable` for injected instances needing bindings
- **SwiftData**: `@Model` for persistence, `@Query` in leaf views, `ModelContext` for writes in ViewModels
- **Domain purity**: `Domain/` contains zero UI dependencies. Test with Swift Testing (`@Test`, `#expect`), no simulator needed
- **iOS 26+ only**: No `#available` guards needed for base APIs. Use Liquid Glass on navigation layer only (system tab bar, glass button styles, toolbar controls). Never on content cards or data lists
- **Temperature**: All internal temps in Celsius. Display conversion is a presentation concern only
- **Enums as String rawValues**: SwiftData `@Model` types store enum values as `String` rawValues for reliability and debuggability

## Recipes

Four built-in recipes defined in `Models/Static/RecipeBook.swift` as static constants. Read-only in v1 — no custom recipe editor. Each recipe has an ingredients list and an ordered method (array of `MethodStep`). The scheduler is agnostic to step names — it only reads classification and duration rules.

Step classifications:
- `handsOn` — must avoid unavailable windows
- `passiveFlexible` — can stretch/compress within a range
- `passiveFixed` — fixed duration, runs through anything

## Schedule Builder Algorithm

Works backwards from target bread-ready time. Iterates method steps in reverse, subtracting durations and checking hands-on steps against availability. Flexible steps (autolyse, cold retard) absorb conflicts by compressing/expanding within their range. When local resolution fails, packages conflict data for LLM resolution.

## API Keys

Anthropic API key via xcconfig pattern:
- `Secrets.xcconfig` (gitignored) holds `ANTHROPIC_API_KEY`
- `Config.swift` reads from `Bundle.main.infoDictionary`
- Copy `Secrets.example.xcconfig` to `Secrets.xcconfig` and fill in real values

## Testing

Swift Testing (`@Test`, `#expect`) for unit tests. XCTest for UI tests.

Domain tests are the priority — they validate the scheduler, temperature math, degree-hours, and hydration calculations as pure Swift functions without needing UI or SwiftData. ViewModel tests use in-memory `ModelContainer`. UI tests cover critical flows (onboarding, schedule creation).
