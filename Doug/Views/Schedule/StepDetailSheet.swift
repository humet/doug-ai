import SwiftData
import SwiftUI

/// Full-controls sheet for a `ScheduleStep`. Renders a mode-aware detail view:
/// - Upcoming: instructions + adjustment controls
/// - Active: instructions + Done + temp-entry handoff + controls
/// - Done / Skipped: summary + Go Back (if it's the most-recent)
struct StepDetailSheet: View {
    let step: ScheduleStep
    @Bindable var viewModel: ScheduleViewModel
    let isMostRecentlyCompleted: Bool
    var starterProfile: StarterProfile?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showTemperatureEntry = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(now: context.date)
                        instructions
                        if isStarterRelatedStep, step.stepStatus == .active {
                            feedSettingsSection
                        }
                        if step.stepStatus == .active, step.stepType.requiresTempReading {
                            temperatureEntryButton
                        }
                        if showsMarkDoneButton {
                            markDoneButton
                        }
                        if step.stepStatus == .done || step.stepStatus == .skipped {
                            if isMostRecentlyCompleted {
                                reopenButton
                            }
                            historyBlock
                        } else if step.stepStatus == .upcoming {
                            delayControls
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(step.stepType.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showTemperatureEntry) {
            if let schedule = step.schedule {
                TemperatureEntryView(
                    schedule: schedule,
                    foldStep: step,
                    onSave: { viewModel.handleNewTemperatureReading(schedule: schedule) }
                )
            }
        }
    }

    // MARK: - Header

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StepTypeIconView(stepTypeID: stepTypeIDEnum, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.stepType.label)
                        .font(.title3.bold())
                    StepCountdownLabel(step: step, referenceDate: now)
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 16) {
                scheduledTime(label: "Start", time: step.computedStartTime)
                scheduledTime(label: "End", time: step.computedEndTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 16))
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = switch step.stepStatus {
        case .upcoming: ("Upcoming", DougTheme.stepUpcoming)
        case .active: ("Active", DougTheme.stepActive)
        case .done: ("Done", DougTheme.stepDone)
        case .skipped: ("Skipped", DougTheme.stepSkipped)
        }
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: .capsule)
    }

    private func scheduledTime(label: String, time: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(time, style: .time)
        }
    }

    // MARK: - Instructions

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What to do")
                .font(.subheadline.bold())
            contextualIngredients
            Text(StepTypeRegistry.instructionText(
                for: stepTypeIDEnum,
                storage: starterProfile?.starterStorageType,
                recipe: step.schedule?.recipe
            ))
            .font(.subheadline)
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
            Text("You'll know it's done when")
                .font(.subheadline.bold())
                .padding(.top, 8)
            Text(step.stepType.successSignal)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var contextualIngredients: some View {
        if let ing = step.schedule?.recipe.ingredients {
            let items: [(String, Double)] = switch stepTypeIDEnum {
            case .buildLevain: levainBuildWeights(ingredients: ing)
            case .autolyse: [("Flour", ing.flourGrams), ("Water", ing.waterGrams)]
            case .mix: [
                ("Flour", ing.flourGrams),
                ("Water", ing.waterGrams),
                ("Levain", ing.levainGrams),
                ("Salt", ing.saltGrams),
            ] + ing.extras.filter { $0.incorporation == .mix }.map { ($0.name, $0.grams) }
            case .addInclusions: ing.extras.filter { $0.incorporation == .fold }.map { ($0.name, $0.grams) }
            default: []
            }
            if !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider() }
                        HStack {
                            Text(item.0)
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(item.1.rounded()))g")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                    if let waterTemp = desiredWaterTemperature {
                        Divider()
                        HStack {
                            Label("Water temperature", systemImage: "drop.fill")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("\(Int(waterTemp.rounded()))°C")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(10)
                .background(DougTheme.warmWheat.opacity(0.3), in: .rect(cornerRadius: 10))
            }
        }
    }

    private var desiredWaterTemperature: Double? {
        guard let schedule = step.schedule else { return nil }
        switch stepTypeIDEnum {
        case .autolyse:
            return TemperatureCalculator.desiredWaterTemperature(
                desiredDoughTemp: schedule.recipe.referenceTemperatureCelsius,
                kitchenTemp: schedule.kitchenTemperatureCelsius,
                restMinutes: step.computedDurationMinutes,
                includeLevain: false
            )
        case .buildLevain:
            return TemperatureCalculator.desiredLevainWaterTemperature(
                referenceDoughTemp: schedule.recipe.referenceTemperatureCelsius,
                kitchenTemp: schedule.kitchenTemperatureCelsius
            )
        default:
            return nil
        }
    }

    private var ovenTemperature: Int? {
        guard [.preheat, .bakeCovered, .bakeUncovered].contains(stepTypeIDEnum) else { return nil }
        return step.schedule?.recipe.bakeTemperature(for: stepTypeIDEnum)
    }

    // MARK: - Primary actions

    private var temperatureEntryButton: some View {
        Button {
            showTemperatureEntry = true
        } label: {
            Label("Enter Temperature", systemImage: "thermometer.medium")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .adaptiveGlassButtonStyle(prominent: true)
    }

    private var markDoneButton: some View {
        Button {
            viewModel.markStepDone(step, modelContext: modelContext)
            dismiss()
        } label: {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .adaptiveGlassButtonStyle(prominent: true)
    }

    private var reopenButton: some View {
        Button {
            viewModel.reopenStep(step, modelContext: modelContext)
            dismiss()
        } label: {
            Label("Go Back to This Step", systemImage: "arrow.uturn.backward.circle")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .adaptiveGlassButtonStyle()
    }

    // MARK: - History block (done / skipped)

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let actualEnd = step.actualEndTime {
                Label {
                    Text("Finished at \(actualEnd, style: .time)")
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            let readings = (step.schedule?.temperatureReadings ?? []).filter {
                $0.associatedStepTypeID == step.stepTypeID
            }
            if !readings.isEmpty {
                let latest = readings.sorted { $0.timestamp < $1.timestamp }.last!
                Label {
                    Text(String(format: "Logged %.1f°C", latest.temperatureCelsius))
                } icon: {
                    Image(systemName: "thermometer.medium")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 14))
    }

    // MARK: - Delay controls (upcoming steps)

    private var delayControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Running late?")
                .font(.subheadline.weight(.semibold))
            Text("Push this step and everything after it forward.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach([15.0, 30.0, 60.0, 120.0], id: \.self) { minutes in
                    Button {
                        viewModel.delayStep(step, byMinutes: minutes, modelContext: modelContext)
                        dismiss()
                    } label: {
                        Text(formatDelay(minutes))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .adaptiveGlassButtonStyle()
                }
            }
        }
        .padding()
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 14))
    }

    private func formatDelay(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 60 { return "+\(m / 60)h" }
        return "+\(m)m"
    }

    // MARK: - Derived

    private var stepTypeIDEnum: StepTypeID {
        StepTypeID(rawValue: step.stepTypeID) ?? .mix
    }

    private var isStarterRelatedStep: Bool {
        let id = stepTypeIDEnum
        return id == .activateStarter || id == .buildLevain || id == .refeedAndRefrigerate
    }

    private var feedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feed Settings")
                .font(.subheadline.bold())

            HStack {
                Text("Ratio")
                    .font(.subheadline)
                Spacer()
                Stepper(
                    "\(viewModel.feedRatioStarter):\(viewModel.feedRatioFlour):\(viewModel.feedRatioWater)",
                    value: $viewModel.feedRatioFlour,
                    in: 1 ... 20
                )
                .font(.subheadline)
            }

            HStack {
                Text("Starter")
                    .font(.subheadline)
                Spacer()
                TextField("10", text: $viewModel.feedStarterGrams)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 60)
                    .font(.subheadline)
                Text("g")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let grams = Double(viewModel.feedStarterGrams), grams > 0 {
                let flourGrams = grams * Double(viewModel.feedRatioFlour) / Double(max(viewModel.feedRatioStarter, 1))
                let waterGrams = grams * Double(viewModel.feedRatioWater) / Double(max(viewModel.feedRatioStarter, 1))
                HStack {
                    HStack(spacing: 4) {
                        Text("Flour").font(.subheadline)
                        Text("\(Int(flourGrams))g").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Water").font(.subheadline)
                        Text("\(Int(waterGrams))g").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Total").font(.subheadline.weight(.medium))
                        Text("\(Int(grams + flourGrams + waterGrams))g").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text("Kitchen")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(viewModel.feedKitchenTemp))°C")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Stepper("", value: $viewModel.feedKitchenTemp, in: 15 ... 35, step: 1)
                    .labelsHidden()
            }
        }
        .padding()
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 14))
        .onAppear { viewModel.initializeFeedDefaults(for: step) }
    }

    private func levainBuildWeights(ingredients: Ingredients) -> [(String, Double)] {
        if let grams = Double(viewModel.feedStarterGrams), grams > 0 {
            let flour = grams * Double(viewModel.feedRatioFlour) / Double(max(viewModel.feedRatioStarter, 1))
            let water = grams * Double(viewModel.feedRatioWater) / Double(max(viewModel.feedRatioStarter, 1))
            return [("Starter", grams), ("Flour", flour), ("Water", water)]
        }
        return [("Levain", ingredients.levainGrams)]
    }

    private var showsMarkDoneButton: Bool {
        guard step.stepStatus == .active else { return false }
        guard step.stepType.classification == .handsOn else { return false }
        if step.stepType.requiresTempReading { return false }
        return true
    }
}
