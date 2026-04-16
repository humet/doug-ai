import SwiftUI
import SwiftData

struct ScheduleTab: View {
    @State private var viewModel = ScheduleViewModel()
    @State private var showConfig = false
    @Namespace private var glassNamespace

    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]
    @Query private var profiles: [StarterProfile]
    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    morphRegion
                    if let schedule = viewModel.activeSchedule {
                        activeBakeRest(schedule: schedule)
                    }
                }
                .padding()
            }
            .background(DougTheme.warmCream)
            .navigationTitle("Schedule")
            .sheet(isPresented: $showConfig) {
                ScheduleConfigSheet(viewModel: viewModel) {
                    // Pre-bake starter health check
                    let canBake = viewModel.preBakeHealthCheck(
                        profile: profiles.first,
                        feedLogs: feedLogs
                    )
                    if canBake {
                        withAnimation(.smooth) {
                            viewModel.startBake(modelContext: modelContext)
                        }
                        showConfig = false
                    }
                }
            }
            .sheet(isPresented: $viewModel.showConflictSheet) {
                if let conflict = viewModel.conflict {
                    ConflictResolutionSheet(
                        conflict: conflict,
                        recipe: viewModel.selectedRecipe,
                        kitchenTemp: viewModel.kitchenTemperature
                    ) { option in
                        viewModel.apply(
                            option: option,
                            availability: availabilities.first,
                            windows: Array(windows),
                            feedLogs: Array(feedLogs)
                        )
                    }
                }
            }
            .sheet(isPresented: $viewModel.showColdRetardSlider) {
                if let step = viewModel.coldRetardStep,
                   let range = viewModel.coldRetardFlexRange {
                    ColdRetardSliderView(
                        coldRetardStep: step,
                        flexRange: range
                    ) { newDuration in
                        viewModel.adjustColdRetard(to: newDuration, modelContext: modelContext)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showTemperatureEntry) {
                if let schedule = viewModel.activeSchedule {
                    TemperatureEntryView(
                        schedule: schedule,
                        foldStep: viewModel.selectedFoldStep
                    )
                }
            }
            .sheet(item: $viewModel.pendingFoldEntry) { entry in
                if let schedule = viewModel.activeSchedule {
                    TemperatureEntryView(
                        schedule: schedule,
                        foldStep: schedule.steps.first {
                            $0.stepTypeID == entry.stepTypeID
                                && $0.sequenceIndex == entry.sequenceIndex
                        }
                    )
                }
            }
            .alert(
                "Starter Not Ready",
                isPresented: Binding(
                    get: { viewModel.starterHealthBlock != nil },
                    set: { if !$0 { viewModel.starterHealthBlock = nil } }
                )
            ) {
                Button("OK") { viewModel.starterHealthBlock = nil }
            } message: {
                if viewModel.starterHealthBlock == .needsRevival {
                    Text("Your starter needs revival before baking. Check the Starter tab for a revival plan.")
                } else {
                    Text("Your starter needs a feed before baking. Feed it and wait for it to peak, then try again.")
                }
            }
        }
    }

    // MARK: - Morph Region

    @ViewBuilder
    private var morphRegion: some View {
        if reduceTransparency {
            morphContent
        } else {
            GlassEffectContainer(spacing: 16) {
                morphContent
            }
        }
    }

    @ViewBuilder
    private var morphContent: some View {
        if let schedule = viewModel.activeSchedule {
            activeHeader(schedule: schedule)
        } else {
            recipeSelection
        }
    }

    // MARK: - Recipe Selection

    private var recipeSelection: some View {
        VStack(spacing: 16) {
            ForEach(RecipeBook.all) { recipe in
                RecipeCard(
                    recipe: recipe,
                    isSelected: recipe.id == viewModel.selectedRecipeID,
                    glassNamespace: glassNamespace,
                    reduceTransparency: reduceTransparency
                ) {
                    withAnimation(.smooth) {
                        viewModel.selectedRecipeID = recipe.id
                    }
                }
            }

            Button {
                viewModel.buildPreview(
                    availability: availabilities.first,
                    windows: Array(windows),
                    feedLogs: Array(feedLogs)
                )
                if viewModel.conflict == nil {
                    showConfig = true
                }
            } label: {
                Label("Plan Bake", systemImage: "calendar.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.glassProminent)
            .padding(.top, 8)
        }
    }

    // MARK: - Active Bake

    @ViewBuilder
    private func activeHeader(schedule: Schedule) -> some View {
        let header = HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.recipe.name)
                    .font(.title2.bold())
                Text("Bread ready \(schedule.targetBreadReadyTime, style: .relative)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Active")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.green, in: .capsule)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)

        if reduceTransparency {
            header.background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        } else {
            header
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .glassEffectID("selectedRecipe", in: glassNamespace)
        }
    }

    @ViewBuilder
    private func activeBakeRest(schedule: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DegreeHoursChartView(
                readings: schedule.temperatureReadings,
                targetDegreeHours: schedule.recipe.degreeHourTarget
            )

            Button {
                viewModel.showColdRetardSlider = true
            } label: {
                Label("Adjust Cold Retard", systemImage: "clock.arrow.2.circlepath")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)

            let sortedSteps = schedule.steps
                .filter { $0.parentStep == nil }
                .sorted { $0.sequenceIndex < $1.sequenceIndex }

            ForEach(sortedSteps) { step in
                StepTimelineRow(step: step)
                    .onTapGesture {
                        if step.stepType.requiresTempReading || !step.subSteps.isEmpty {
                            viewModel.selectedFoldStep = step
                            viewModel.showTemperatureEntry = true
                        }
                    }

                ForEach(step.subSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }) { subStep in
                    StepTimelineRow(step: subStep)
                        .padding(.leading, 24)
                        .onTapGesture {
                            if subStep.stepType.requiresTempReading {
                                viewModel.selectedFoldStep = subStep
                                viewModel.showTemperatureEntry = true
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Recipe Card

private struct RecipeCard: View {
    let recipe: Recipe
    let isSelected: Bool
    let glassNamespace: Namespace.ID
    let reduceTransparency: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(recipe.name)
                        .font(.headline)
                    Spacer()
                    Text("\(recipe.hydrationPercent)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(recipe.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    Label(recipe.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                    Spacer()
                    Label("\(recipe.approximateTotalHours.lowerBound)–\(recipe.approximateTotalHours.upperBound)h", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(RecipeCardBackground(
                isSelected: isSelected,
                glassNamespace: glassNamespace,
                reduceTransparency: reduceTransparency
            ))
        }
        .buttonStyle(.plain)
    }
}

private struct RecipeCardBackground: ViewModifier {
    let isSelected: Bool
    let glassNamespace: Namespace.ID
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        Group {
            if isSelected, !reduceTransparency {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    .glassEffectID("selectedRecipe", in: glassNamespace)
            } else if isSelected, reduceTransparency {
                content
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
            } else {
                content
                    .background(Color(.systemBackground), in: .rect(cornerRadius: 16))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }
}

// MARK: - Step Timeline Row

struct StepTimelineRow: View {
    let step: ScheduleStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(step.stepType.label)
                        .font(.subheadline.bold())
                    if step.stepType.requiresTempReading {
                        Image(systemName: "thermometer.medium")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack {
                    Text(step.computedStartTime, style: .time)
                    Text("–")
                    Text(step.computedEndTime, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer()

            Text(formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch step.stepStatus {
        case .upcoming: DougTheme.stepUpcoming
        case .active: DougTheme.stepActive
        case .done: DougTheme.stepDone
        case .skipped: DougTheme.stepSkipped
        }
    }

    private var formattedDuration: String {
        let minutes = Int(step.computedDurationMinutes)
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

#Preview {
    ScheduleTab()
        .modelContainer(for: Schedule.self, inMemory: true)
}
