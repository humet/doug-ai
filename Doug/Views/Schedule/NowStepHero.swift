import SwiftData
import SwiftUI

/// Prominent hero card for the currently-active (or most-imminent upcoming) step.
struct NowStepHero: View {
    let step: ScheduleStep
    let viewModel: ScheduleViewModel
    let referenceDate: Date
    let onOpenDetail: (ScheduleStep) -> Void
    var onOpenCoach: ((String) -> Void)?
    var starterProfile: StarterProfile?

    @Environment(\.modelContext) private var modelContext
    @State private var showTemperatureEntry = false
    @State private var showAbandonConfirm = false
    @State private var showAlreadyStarted = false
    @State private var feedRatioStarter: Int = 1
    @State private var feedRatioFlour: Int = 5
    @State private var feedRatioWater: Int = 5
    @State private var feedStarterGrams: String = ""
    @State private var feedKitchenTemp: Double = 22
    @State private var feedInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            contextualInfo

            if let info = stalenessInfo {
                stalenessWarning(info)
            } else {
                Text(step.stepType.instructionText)
                    .font(.subheadline)

                ovenTemperatureCallout

                if !step.stepType.successSignal.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(step.stepType.successSignal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            activeFoldCallout
            bakePhaseCallout
            inlineFeedEntry
            primaryActions
            secondaryActions
            subStepsList
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(accentTint.opacity(0.35), lineWidth: 1.5)
        )
        .sheet(isPresented: $showTemperatureEntry) {
            if let schedule = step.schedule {
                TemperatureEntryView(
                    schedule: schedule,
                    foldStep: stepRequiringTemp,
                    onSave: {
                        if let tempStep = stepRequiringTemp, tempStep.parentStep == nil {
                            viewModel.finishStepEarly(tempStep, modelContext: modelContext)
                        }
                        viewModel.handleNewTemperatureReading(schedule: schedule)
                    }
                )
            }
        }
        .sheet(isPresented: $showAlreadyStarted) {
            AlreadyStartedSheet(step: step, viewModel: viewModel)
        }
        .confirmationDialog(
            "Abandon this bake?",
            isPresented: $showAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandon Bake", role: .destructive) {
                viewModel.cancelBake(modelContext: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let info = stalenessInfo {
                Text(info.salvageAdvice)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            StepTypeIconView(stepTypeID: stepTypeIDEnum, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentTint)
                Text(step.stepType.label)
                    .font(.title2.bold())
                StepCountdownLabel(step: step, referenceDate: referenceDate)
                    .font(.subheadline.monospacedDigit())
            }
            Spacer()
            Button {
                onOpenDetail(step)
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(.rect)
            }
        }
    }

    // MARK: - Staleness

    private func stalenessWarning(_ info: StalenessInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(info.warning)
                    .font(.subheadline)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text(info.salvageAdvice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if onOpenCoach != nil {
                let delay = Int(referenceDate.timeIntervalSince(step.computedStartTime) / 60)
                let temp = step.schedule?.kitchenTemperatureCelsius ?? 22
                Button {
                    onOpenCoach?(
                        "I'm \(delay) minutes late for \(step.stepType.label). Kitchen is \(Int(temp))°C. What should I do?"
                    )
                } label: {
                    Label("What should I do?", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .adaptiveGlassButtonStyle()
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
    }

    // MARK: - Primary actions

    private var primaryActions: some View {
        HStack(spacing: 10) {
            if showsStart, stalenessInfo != nil {
                Button {
                    viewModel.startStepNow(step, modelContext: modelContext)
                } label: {
                    Label("Start Anyway", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle()
                Button {
                    showAbandonConfirm = true
                } label: {
                    Label("Abandon", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle()
            } else if showsStart {
                Button {
                    viewModel.startStepNow(step, modelContext: modelContext)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
                Button {
                    showAlreadyStarted = true
                } label: {
                    Label("Already Started", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle()
            } else if step.stepType.requiresTempReading, step.stepStatus == .active {
                Button {
                    showTemperatureEntry = true
                } label: {
                    Label("Done — Log Temp", systemImage: "thermometer.medium")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
            } else if activeFoldWithTempReading != nil {
                Button {
                    showTemperatureEntry = true
                } label: {
                    Label("Log Temp", systemImage: "thermometer.medium")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
            } else if isBulkFermentActive {
                if viewModel.bulkFermentTargetReached {
                    Label("Fermentation target reached", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    showTemperatureEntry = true
                } label: {
                    Label("Log Temp", systemImage: "thermometer.medium")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
                Button {
                    completeCurrent()
                } label: {
                    Label("Finish Early", systemImage: "forward.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle()
            } else if step.stepStatus == .active {
                let isOverdueFlexible = step.stepType.classification == .passiveFlexible
                    && step.computedEndTime <= referenceDate
                let isPassive = step.stepType.classification != .handsOn

                if let activeSub = activeBakeSubStep {
                    let isSubOverdue = activeSub.computedEndTime <= referenceDate
                    let isCovered = activeSub.stepTypeID == StepTypeID.bakeCovered.rawValue
                    Button {
                        viewModel.markStepDone(activeSub, modelContext: modelContext)
                    } label: {
                        Label(
                            isSubOverdue
                                ? (isCovered ? "Remove Lid" : "Done")
                                : (isCovered ? "Remove Lid Early" : "Finish Early"),
                            systemImage: isSubOverdue ? "checkmark.circle.fill" : "forward.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .adaptiveGlassButtonStyle(prominent: isSubOverdue)
                } else {
                    let buttonLabel = if isWaitForPeakStep || isLevainAwaitingPeak {
                        "Mark Peak"
                    } else if isOverdueFlexible {
                        "Move On"
                    } else if isPassive {
                        "Finish Early"
                    } else {
                        "Done"
                    }
                    let buttonIcon = if isWaitForPeakStep || isLevainAwaitingPeak {
                        "arrow.up.to.line"
                    } else if isOverdueFlexible {
                        "checkmark.circle.fill"
                    } else if isPassive {
                        "forward.fill"
                    } else {
                        "checkmark.circle.fill"
                    }
                    Button {
                        completeCurrent()
                    } label: {
                        Label(buttonLabel, systemImage: buttonIcon)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .adaptiveGlassButtonStyle(
                        prominent: isWaitForPeakStep || isLevainAwaitingPeak || isOverdueFlexible || !isPassive
                    )
                }
            }
        }
    }

    // MARK: - Secondary actions

    @ViewBuilder
    private var secondaryActions: some View {
        if isPaused {
            Button {
                viewModel.resumeSchedule(modelContext: modelContext)
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .adaptiveGlassButtonStyle()
        } else if step.stepStatus == .upcoming, !showsStart {
            VStack(spacing: 8) {
                Text("Running late?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    ForEach([15.0, 30.0, 60.0], id: \.self) { minutes in
                        Button {
                            viewModel.delayStep(step, byMinutes: minutes, modelContext: modelContext)
                        } label: {
                            Text(minutes < 60 ? "+\(Int(minutes))m" : "+1h")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .adaptiveGlassButtonStyle()
                    }
                }
            }
        } else if step.stepStatus == .active {
            HStack(spacing: 10) {
                Button {
                    viewModel.extendStep(step, byMinutes: 15, modelContext: modelContext)
                } label: {
                    Label("+15m", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .adaptiveGlassButtonStyle()

                Button {
                    viewModel.extendStep(step, byMinutes: 30, modelContext: modelContext)
                } label: {
                    Label("+30m", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .adaptiveGlassButtonStyle()

                Button {
                    viewModel.pauseSchedule(modelContext: modelContext)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .adaptiveGlassButtonStyle()
            }
        }
    }

    // MARK: - Oven temperature callout

    @ViewBuilder
    private var ovenTemperatureCallout: some View {
        if let temp = ovenTemperature {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("\(temp)°C")
                    .font(.title2.bold().monospacedDigit())
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Contextual measurements

    @ViewBuilder
    private var contextualInfo: some View {
        if let ing = recipeIngredients {
            switch stepTypeIDEnum {
            case .buildLevain:
                measurementChips([("Levain", ing.levainGrams)])
            case .autolyse:
                VStack(alignment: .leading, spacing: 6) {
                    measurementChips([("Flour", ing.flourGrams), ("Water", ing.waterGrams)])
                    waterTemperatureCallout
                }
            case .mix:
                measurementChips([
                    ("Flour", ing.flourGrams),
                    ("Water", ing.waterGrams),
                    ("Levain", ing.levainGrams),
                    ("Salt", ing.saltGrams),
                ])
            case .addInclusions where !ing.extras.isEmpty:
                measurementChips(ing.extras.map { ($0.name, $0.grams) })
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var waterTemperatureCallout: some View {
        if let waterTemp = desiredWaterTemperature {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Water at \(Int(waterTemp.rounded()))°C")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.blue.opacity(0.1), in: .capsule)
        }
    }

    private func measurementChips(_ items: [(String, Double)]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text("\(item.0) \(Int(item.1.rounded()))g")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DougTheme.warmWheat.opacity(0.5), in: .capsule)
            }
        }
    }

    // MARK: - Fold callout

    @ViewBuilder
    private var activeFoldCallout: some View {
        if let fold = activeFoldWithTempReading {
            VStack(alignment: .leading, spacing: 6) {
                Label(fold.stepType.label, systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Once you've folded, log your dough temperature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Bake phase callout

    @ViewBuilder
    private var bakePhaseCallout: some View {
        if stepTypeIDEnum == .bake,
           let covered = step.subSteps.first(where: {
               $0.stepTypeID == StepTypeID.bakeCovered.rawValue && $0.stepStatus == .active
           }),
           covered.computedEndTime <= referenceDate {
            VStack(alignment: .leading, spacing: 6) {
                Label("Remove the Lid", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("The covered phase is done. Remove the lid and tap Done to start the uncovered bake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Substeps

    @ViewBuilder
    private var subStepsList: some View {
        let subs = step.subSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        if !subs.isEmpty {
            Divider()
                .padding(.vertical, 2)

            Text(stepTypeIDEnum == .bake ? "Bake Stages" : "Stretch & Folds")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(subs) { sub in
                CompactStepRow(
                    step: sub,
                    referenceDate: referenceDate,
                    isSubStep: true,
                    onTap: { onOpenDetail(sub) }
                )
            }
        }
    }

    // MARK: - Derived

    private var stepTypeIDEnum: StepTypeID {
        StepTypeID(rawValue: step.stepTypeID) ?? .mix
    }

    private var eyebrow: String {
        switch step.stepStatus {
        case .active: "Now"
        case .upcoming: "Up next"
        case .done: "Completed"
        case .skipped: "Skipped"
        }
    }

    private var accentTint: Color {
        StepTypeIcon.tint(for: stepTypeIDEnum)
    }

    private var ovenTemperature: Int? {
        guard [.preheat, .bake, .bakeCovered, .bakeUncovered].contains(stepTypeIDEnum) else { return nil }
        return step.schedule?.recipe.bakeTemperature(for: stepTypeIDEnum)
    }

    private var recipeIngredients: Ingredients? {
        step.schedule?.recipe.ingredients
    }

    private var desiredWaterTemperature: Double? {
        guard stepTypeIDEnum == .autolyse,
              let schedule = step.schedule else { return nil }
        return TemperatureCalculator.desiredWaterTemperature(
            desiredDoughTemp: schedule.recipe.referenceTemperatureCelsius,
            kitchenTemp: schedule.kitchenTemperatureCelsius,
            restMinutes: step.computedDurationMinutes,
            includeLevain: false
        )
    }

    private var stalenessInfo: StalenessInfo? {
        guard showsStart,
              let staleness = step.stepType.staleness
        else { return nil }
        let delay = referenceDate.timeIntervalSince(step.computedStartTime) / 60
        guard delay >= staleness.thresholdMinutes else { return nil }
        return staleness
    }

    private var showsStart: Bool {
        step.stepStatus == .upcoming
            && referenceDate >= step.computedStartTime
    }

    private var isBulkFermentActive: Bool {
        stepTypeIDEnum == .bulkFerment && step.stepStatus == .active
    }

    private var activeFoldWithTempReading: ScheduleStep? {
        guard isBulkFermentActive else { return nil }
        return step.subSteps
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .first { $0.stepStatus == .active && $0.stepType.requiresTempReading }
    }

    private var activeBakeSubStep: ScheduleStep? {
        guard stepTypeIDEnum == .bake else { return nil }
        return step.subSteps
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .first { $0.stepStatus == .active }
    }

    private var stepRequiringTemp: ScheduleStep? {
        activeFoldWithTempReading
            ?? (step.stepType.requiresTempReading && step.stepStatus == .active ? step : nil)
    }

    private var isPaused: Bool {
        step.schedule?.pausedAt != nil
    }

    private var isStarterRelatedStep: Bool {
        let id = stepTypeIDEnum
        return id == .activateStarter || id == .buildLevain || id == .refeedAndRefrigerate
    }

    private var isWaitForPeakStep: Bool {
        stepTypeIDEnum == .waitForPeak
    }

    private var isLevainAwaitingPeak: Bool {
        stepTypeIDEnum == .buildLevain && step.computedEndTime <= Date()
    }

    @ViewBuilder
    private var inlineFeedEntry: some View {
        if isStarterRelatedStep, step.stepStatus == .active {
            InlineFeedEntryView(
                ratioStarter: $feedRatioStarter,
                ratioFlour: $feedRatioFlour,
                ratioWater: $feedRatioWater,
                starterGrams: $feedStarterGrams,
                kitchenTemp: $feedKitchenTemp
            )
            .onAppear { initializeFeedDefaults() }
        }
    }

    private func initializeFeedDefaults() {
        guard !feedInitialized else { return }
        feedInitialized = true
        let temp = step.schedule?.kitchenTemperatureCelsius ?? 22
        feedKitchenTemp = temp
        switch stepTypeIDEnum {
        case .activateStarter:
            feedRatioStarter = 1; feedRatioFlour = 5; feedRatioWater = 5
        case .buildLevain:
            if let recipe = step.schedule?.recipe {
                let kitchenTemp = step.schedule?.kitchenTemperatureCelsius ?? temp
                let build = LevainBuildCalculator.calculate(.init(
                    levainGramsNeeded: recipe.ingredients.levainGrams,
                    baseRatio: recipe.levainBuildRatio,
                    referenceTemp: recipe.referenceTemperatureCelsius,
                    kitchenTemp: kitchenTemp
                ))
                feedRatioStarter = build.ratio.starter
                feedRatioFlour = build.ratio.flour
                feedRatioWater = build.ratio.water
                feedStarterGrams = String(Int(build.starterGrams))
            } else {
                feedRatioStarter = 1; feedRatioFlour = 5; feedRatioWater = 5
            }
        case .refeedAndRefrigerate:
            feedRatioStarter = 1; feedRatioFlour = 1; feedRatioWater = 1
            feedStarterGrams = "10"
        default:
            break
        }
    }

    private var currentFeedDetails: FeedDetails {
        FeedDetails(
            ratioStarter: feedRatioStarter,
            ratioFlour: feedRatioFlour,
            ratioWater: feedRatioWater,
            flourType: "white",
            kitchenTemperatureCelsius: feedKitchenTemp,
            starterGrams: Double(feedStarterGrams)
        )
    }

    private func completeCurrent() {
        if isStarterRelatedStep || isWaitForPeakStep || isLevainAwaitingPeak {
            viewModel.markStepDone(
                step,
                feedDetails: isStarterRelatedStep ? currentFeedDetails : nil,
                starterProfile: starterProfile,
                modelContext: modelContext
            )
        } else if step.stepType.classification == .handsOn {
            viewModel.markStepDone(step, modelContext: modelContext)
        } else {
            viewModel.finishStepEarly(step, modelContext: modelContext)
        }
    }
}

// MARK: - Already Started Sheet

private struct AlreadyStartedSheet: View {
    let step: ScheduleStep
    let viewModel: ScheduleViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var startTime: Date

    init(step: ScheduleStep, viewModel: ScheduleViewModel) {
        self.step = step
        self.viewModel = viewModel
        let earliest = Calendar.current.startOfDay(for: Date())
        let initial = max(earliest, step.computedStartTime)
        _startTime = State(initialValue: initial)
    }

    private var earliestAllowed: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Started at",
                        selection: $startTime,
                        in: earliestAllowed ... Date(),
                        displayedComponents: [.hourAndMinute]
                    )
                } footer: {
                    Text("Pick when you actually started this step. The rest of the schedule will shift to match.")
                }
            }
            .navigationTitle("Already Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.startStepAt(step, at: startTime, modelContext: modelContext)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
