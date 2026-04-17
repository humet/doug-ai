import SwiftData
import SwiftUI

/// Two-step input sheet shown before a revival plan is generated.
///
/// Step 1 captures what the user sees (days since last fed, hooch, smell, a
/// safety gate for contamination, and optional free-text). If the gate fires we
/// show a terminal "don't revive" card and no plan is created. Step 2 collects
/// the measurements needed to produce the plan's gram amounts.
struct StartRevivalSheet: View {
    @Bindable var viewModel: StarterViewModel
    let profile: StarterProfile?
    let availability: UserAvailability?
    let windows: [UnavailableWindow]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var wizardStage: Stage = .condition

    private enum Stage {
        case condition
        case measurements
    }

    private enum DaysBucket: String, CaseIterable, Identifiable {
        case lessThanWeek = "< 1 week"
        case oneToTwo = "1–2 weeks"
        case twoToFour = "2–4 weeks"
        case fourPlus = "4+ weeks"
        case notSure = "Not sure"

        var id: String {
            rawValue
        }

        var estimatedDays: Int? {
            switch self {
            case .lessThanWeek: 3
            case .oneToTwo: 10
            case .twoToFour: 21
            case .fourPlus: 35
            case .notSure: nil
            }
        }
    }

    @State private var daysBucket: DaysBucket = .oneToTwo
    @State private var startMode: StartMode = .now

    private enum StartMode: Hashable {
        case now
        case delayed(Date)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch wizardStage {
                case .condition:
                    conditionStage
                case .measurements:
                    measurementsStage
                }
            }
            .navigationTitle(wizardStage == .condition ? "How does it look?" : "Measurements")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    trailingToolbarButton
                }
            }
            .interactiveDismissDisabled(viewModel.revivalIsPreparing)
        }
        .onAppear(perform: prefillFromProfile)
    }

    // MARK: - Stage 1 — Condition

    @ViewBuilder
    private var conditionStage: some View {
        Section {
            Picker("Last fed", selection: $daysBucket) {
                ForEach(DaysBucket.allCases) { bucket in
                    Text(bucket.rawValue).tag(bucket)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("How long since the last feed?")
        }

        Section {
            Toggle("Dark liquid (hooch) on top", isOn: $viewModel.revivalHasHooch)
            Toggle("Strong nail-polish / acetone smell", isOn: $viewModel.revivalSmellsAcetone)
            Toggle("Bubbles on the surface", isOn: $viewModel.revivalHasBubbles)
        } header: {
            Text("What do you see?")
        } footer: {
            Text("A faint alcohol smell or a layer of liquid is normal for a hungry starter.")
        }

        Section {
            Toggle("Pink, orange, red, or fuzzy patches", isOn: $viewModel.revivalHasPinkOrangeOrMold)
                .tint(.red)
        } header: {
            Text("Safety check")
        } footer: {
            Text("Unusual colours or visible fuzz are a sign of contamination.")
        }

        Section {
            TextField("Anything else? (optional)", text: $viewModel.revivalNotes, axis: .vertical)
                .lineLimit(3 ... 6)
        } header: {
            Text("Notes")
        } footer: {
            Text("Share anything unusual — colour, smell, texture. Helps tune the guidance.")
        }

        if viewModel.revivalHasPinkOrangeOrMold {
            Section {
                unsafeCard
            }
        }
    }

    private var unsafeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Don't revive this one", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            if case let .discardAndRestart(reason) = viewModel.revivalSafetyVerdict {
                Text(reason)
                    .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Stage 2 — Measurements

    @ViewBuilder
    private var measurementsStage: some View {
        Section {
            HStack {
                Text("Starter amount")
                Spacer()
                TextField("20", text: $viewModel.revivalStarterGrams)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text("g")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("How much starter will you keep?")
        } footer: {
            Text("We'll use the same amount for every feed and scale flour and water around it.")
        }

        Section {
            Picker("Flour type", selection: $viewModel.revivalFlourType) {
                Text("White").tag("white")
                Text("Whole Wheat").tag("whole wheat")
                Text("Rye").tag("rye")
            }

            HStack {
                Text("Kitchen temp")
                Spacer()
                Text("\(Int(viewModel.revivalKitchenTemp))°C")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.revivalKitchenTemp, in: 16 ... 32, step: 1)
        } header: {
            Text("Conditions")
        }

        Section {
            summaryCard
        }

        timingSection

        if viewModel.revivalIsPreparing {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Building your plan…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var timingSection: some View {
        let now = Date()
        let peakMinutes = firstFeedPeakMinutes
        let availInput = availabilityInput
        let windowInputs = windows.map { WindowInput(from: $0) }

        if RevivalTiming.peakFallsInUnavailable(
            startTime: now,
            expectedPeakMinutes: peakMinutes,
            availability: availInput,
            windows: windowInputs
        ) {
            let peakNow = now.addingTimeInterval(peakMinutes * 60)
            let suggested = RevivalTiming.suggestedStartTime(
                currentTime: now,
                expectedPeakMinutes: peakMinutes,
                availability: availInput,
                windows: windowInputs
            )

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz")
                            .foregroundStyle(.orange)
                        Text("Peak will land at \(peakNow, format: .dateTime.hour().minute()) — while you'd usually be asleep.")
                            .font(.footnote)
                    }
                }
                .padding(.vertical, 2)

                Picker("", selection: $startMode) {
                    Text("Mix now").tag(StartMode.now)
                    if let suggested {
                        let suggestedPeak = suggested.addingTimeInterval(peakMinutes * 60)
                        Text("Start at \(suggested, format: .dateTime.weekday(.abbreviated).hour().minute()) (peak at \(suggestedPeak, format: .dateTime.hour().minute()))")
                            .tag(StartMode.delayed(suggested))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Timing")
            } footer: {
                Text("If you mix now, you can mark peak whenever you wake up — the rest of the plan will shift to fit your day.")
            }
        }
    }

    private var firstFeedPeakMinutes: Double {
        let neglect: StarterNeglectLevel
        if case let .safeToRevive(level) = viewModel.revivalSafetyVerdict {
            neglect = level
        } else {
            neglect = .moderate
        }
        return RevivalPlanGenerator.expectedPeakMinutes(
            for: neglect,
            kitchenTempC: viewModel.revivalKitchenTemp
        ).first ?? 360
    }

    private var availabilityInput: AvailabilityInput {
        availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(neglectSummary)
                .font(.callout)
            Text("Expected first peak: \(firstPeakDisplay)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var firstPeakDisplay: String {
        let minutes = firstFeedPeakMinutes
        let hours = minutes / 60
        let rounded = (hours * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "~\(Int(rounded.rounded())) h"
        }
        return "~\(String(format: "%.1f", rounded)) h"
    }

    private var neglectSummary: String {
        guard case let .safeToRevive(level) = viewModel.revivalSafetyVerdict else {
            return ""
        }
        switch level {
        case .mild:
            return "We'll run a standard three-feed revival to get things active again."
        case .moderate:
            return "We'll use a gentler first feed — it's been a while, so expect the first peak to take longer."
        case .severe:
            return "We'll add an extra feed and give the first one plenty of time. Neglected starters need patience."
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var trailingToolbarButton: some View {
        switch wizardStage {
        case .condition:
            Button("Next") {
                viewModel.revivalDaysSinceLastFed = daysBucket.estimatedDays
                wizardStage = .measurements
            }
            .disabled(viewModel.revivalHasPinkOrangeOrMold)
        case .measurements:
            Button {
                Task { await startRevival() }
            } label: {
                if viewModel.revivalIsPreparing {
                    ProgressView()
                } else {
                    Text("Start")
                }
            }
            .disabled(viewModel.revivalIsPreparing || !canStart)
        }
    }

    private var canStart: Bool {
        guard case .safeToRevive = viewModel.revivalSafetyVerdict else { return false }
        let trimmed = viewModel.revivalStarterGrams.trimmingCharacters(in: .whitespaces)
        guard let grams = Double(trimmed), grams > 0 else { return false }
        return true
    }

    // MARK: - Actions

    private func startRevival() async {
        let startAt: Date? = switch startMode {
        case .now: nil
        case let .delayed(date): date
        }
        let plan = await viewModel.startRevival(
            startAt: startAt,
            availability: availability,
            windows: windows,
            modelContext: modelContext
        )
        if plan != nil {
            dismiss()
        }
    }

    private func prefillFromProfile() {
        if let profile {
            viewModel.revivalKitchenTemp = profile.storageType == "counter" ? 22 : 22
        }
    }
}

#Preview {
    StartRevivalSheet(
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
