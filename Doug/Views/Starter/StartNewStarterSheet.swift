import SwiftData
import SwiftUI

/// Two-step sheet for creating a starter that doesn't exist yet.
///
/// Step 1 picks the route — from scratch, a dried culture, a friend's jar, or a
/// shop kit — with honest timings, because "about three weeks" and "about three
/// days" are very different commitments. Step 2 collects the one measurement
/// that route needs, plus kitchen temperature.
struct StartNewStarterSheet: View {
    @Bindable var viewModel: StarterViewModel
    let profile: StarterProfile?
    let availability: UserAvailability?
    let windows: [UnavailableWindow]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var stage: Stage = .route
    @State private var origin: StarterOrigin = .fromScratch
    @State private var seedGrams: String = ""
    @State private var flourType: String = "whole wheat"
    @State private var kitchenTemp: Double = 22
    @State private var startMode: StartMode = .now

    private enum Stage {
        case route
        case measurements
    }

    private enum StartMode: Hashable {
        case now
        case delayed(Date)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case .route:
                    routeStage
                case .measurements:
                    measurementsStage
                }
            }
            .navigationTitle(stage == .route ? "Start a Starter" : "Measurements")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .route ? "Cancel" : "Back") {
                        if stage == .route {
                            dismiss()
                        } else {
                            stage = .route
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    trailingToolbarButton
                }
            }
        }
    }

    // MARK: - Stage 1 — Route

    @ViewBuilder
    private var routeStage: some View {
        Section {
            Text("Where is your starter coming from?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Section {
            ForEach(StarterOrigin.allCases) { option in
                Button {
                    origin = option
                    applyRouteDefaults()
                } label: {
                    routeRow(option)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("starterOrigin-\(option.rawValue)")
                .accessibilityAddTraits(origin == option ? [.isSelected] : [])
            }
        } footer: {
            Text("Timings are a guide, not a promise. Doug adjusts the plan as you tell it what you see.")
        }
    }

    private func routeRow(_ option: StarterOrigin) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: option))
                .font(.title3)
                .foregroundStyle(origin == option ? Color.accentColor : .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title(for: option))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(durationLabel(for: option))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(blurb(for: option))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Image(systemName: origin == option ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(origin == option ? Color.accentColor : Color.secondary.opacity(0.4))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    // MARK: - Stage 2 — Measurements

    @ViewBuilder
    private var measurementsStage: some View {
        Section {
            HStack {
                Text(seedLabel)
                Spacer()
                TextField(seedPlaceholder, text: $seedGrams)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text("g")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(title(for: origin))
        } footer: {
            Text(seedFooter)
        }

        Section {
            Picker("Flour", selection: $flourType) {
                Text("Wholemeal").tag("whole wheat")
                Text("Rye").tag("rye")
                Text("White").tag("white")
            }

            HStack {
                Text("Kitchen temp")
                Spacer()
                Text("\(Int(kitchenTemp))°C")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $kitchenTemp, in: 16 ... 32, step: 1)
        } header: {
            Text("Conditions")
        } footer: {
            Text(flourFooter)
        }

        Section {
            summaryCard
        }

        timingSection
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(planSummary)
                .font(.callout)
            if let ready = estimatedReady {
                Text("Ready around \(ready, format: .dateTime.weekday(.wide).day().month())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Warns when the very first step's peak would land while the user is
    /// asleep. Only the first step can — everything after it is snapped into
    /// available hours by the planner.
    @ViewBuilder
    private var timingSection: some View {
        let steps = previewSteps
        if let first = steps.first, first.expectsPeak {
            let now = Date()
            let availInput = availabilityInput
            let windowInputs = windows.map { WindowInput(from: $0) }

            if RevivalTiming.peakFallsInUnavailable(
                startTime: now,
                expectedPeakMinutes: first.expectedPeakMinutes,
                availability: availInput,
                windows: windowInputs
            ) {
                let peakNow = now.addingTimeInterval(first.expectedPeakMinutes * 60)
                let peakTime = peakNow.formatted(date: .omitted, time: .shortened)
                let suggested = RevivalTiming.suggestedStartTime(
                    currentTime: now,
                    expectedPeakMinutes: first.expectedPeakMinutes,
                    availability: availInput,
                    windows: windowInputs
                )

                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz")
                            .foregroundStyle(.orange)
                        Text(verbatim: "Peak would land at \(peakTime) — while you'd usually be asleep.")
                            .font(.footnote)
                    }
                    .padding(.vertical, 2)

                    Picker("", selection: $startMode) {
                        Text("Start now").tag(StartMode.now)
                        if let suggested {
                            Text("Start at \(suggested, format: .dateTime.weekday(.abbreviated).hour().minute())")
                                .tag(StartMode.delayed(suggested))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Timing")
                } footer: {
                    Text("Starting now is fine too — mark the peak whenever you get to it and the rest shifts to fit.")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var trailingToolbarButton: some View {
        switch stage {
        case .route:
            Button("Next") {
                applyRouteDefaults()
                stage = .measurements
            }
        case .measurements:
            Button("Start") {
                start()
            }
            .disabled(parsedSeedGrams == nil)
        }
    }

    // MARK: - Actions

    private func start() {
        guard let grams = parsedSeedGrams else { return }
        let startAt: Date? = switch startMode {
        case .now: nil
        case let .delayed(date): date
        }

        viewModel.startNewStarter(
            StarterViewModel.NewStarterRequest(
                origin: origin,
                seedGrams: grams,
                flourType: flourType,
                kitchenTempC: kitchenTemp,
                startAt: startAt
            ),
            availability: availability,
            windows: windows,
            profile: profile,
            modelContext: modelContext
        )
        dismiss()
    }

    private func applyRouteDefaults() {
        flourType = StarterOriginPlanner.recommendedFlour(for: origin)
        seedGrams = String(Int(StarterOriginPlanner.defaultSeedGrams(for: origin)))
        startMode = .now
    }

    // MARK: - Derived

    private var parsedSeedGrams: Double? {
        let trimmed = seedGrams.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    private var availabilityInput: AvailabilityInput {
        availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
    }

    private var previewSteps: [StarterProgramStep] {
        StarterOriginPlanner.plan(StarterOriginPlanInput(
            origin: origin,
            startTime: Date(),
            seedGrams: parsedSeedGrams ?? StarterOriginPlanner.defaultSeedGrams(for: origin),
            environment: StarterPlanEnvironment(
                kitchenTempC: kitchenTemp,
                availability: availabilityInput,
                windows: windows.map { WindowInput(from: $0) }
            ),
            flourType: flourType
        ))
    }

    private var estimatedReady: Date? {
        StarterOriginPlanner.estimatedReadyDate(from: previewSteps)
    }

    private var planSummary: String {
        let steps = previewSteps
        let feeds = steps.count
        let days = steps.last?.dayNumber ?? 1
        return "\(feeds) feed\(feeds == 1 ? "" : "s") over about \(days) day\(days == 1 ? "" : "s"). "
            + "Doug will stretch or shorten that based on what you report seeing."
    }
}

// MARK: - Route Copy

private extension StartNewStarterSheet {
    var seedLabel: String {
        switch origin {
        case .fromScratch: "Starting flour"
        case .driedCulture, .shopKit: "Flake weight"
        case .freshGift: "Starter received"
        }
    }

    var seedPlaceholder: String {
        String(Int(StarterOriginPlanner.defaultSeedGrams(for: origin)))
    }

    var seedFooter: String {
        switch origin {
        case .fromScratch:
            "You'll mix this much flour with the same weight of water. 50 g each is a good size — "
                + "big enough to see what's happening, small enough not to waste flour."
        case .driedCulture, .shopKit:
            "Weigh the flakes if you can. If the packet gives its own quantities, use those instead."
        case .freshGift:
            "However much you were given. Doug caps the working amount so you're not feeding half a kilo."
        }
    }

    var flourFooter: String {
        switch origin {
        case .fromScratch, .driedCulture, .shopKit:
            "Wholemeal and rye carry far more wild yeast than white flour, so they get a new starter going faster. "
                + "You can switch to white once it's established."
        case .freshGift:
            "If you know what flour it was raised on, match it for the first few feeds."
        }
    }

    func icon(for option: StarterOrigin) -> String {
        switch option {
        case .fromScratch: "drop.degreesign"
        case .driedCulture: "wind.snow"
        case .freshGift: "gift"
        case .shopKit: "bag"
        }
    }

    func title(for option: StarterOrigin) -> String {
        switch option {
        case .fromScratch: "From scratch"
        case .driedCulture: "Dried culture"
        case .freshGift: "A friend's starter"
        case .shopKit: "Shop-bought kit"
        }
    }

    func blurb(for option: StarterOrigin) -> String {
        switch option {
        case .fromScratch:
            "Just flour and water. You're catching wild yeast from the air and the grain — "
                + "slow, free, and entirely yours."
        case .driedCulture:
            "Freeze-dried flakes from someone else's starter. The culture already exists; you're waking it up."
        case .freshGift:
            "A live jar or a spoonful, handed over. Usually ready after a feed or two in your kitchen."
        case .shopKit:
            "A packaged culture. Works like dried flakes — follow the packet where it differs."
        }
    }

    func durationLabel(for option: StarterOrigin) -> String {
        let range = StarterOriginPlanner.estimatedDays(for: option)
        if range.upperBound >= 14 {
            return "1–3 weeks"
        }
        return "\(range.lowerBound)–\(range.upperBound) days"
    }
}

#Preview {
    StartNewStarterSheet(
        viewModel: StarterViewModel(),
        profile: nil,
        availability: nil,
        windows: []
    )
    .modelContainer(
        for: [RevivalPlan.self, RevivalFeedStep.self, StarterFeedLog.self, StarterProfile.self],
        inMemory: true
    )
}
