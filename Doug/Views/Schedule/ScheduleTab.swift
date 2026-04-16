import SwiftUI
import SwiftData

struct ScheduleTab: View {
    @State private var viewModel = ScheduleViewModel()
    @State private var showConfig = false

    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let schedule = viewModel.activeSchedule {
                        ActiveBakeSection(schedule: schedule)
                    } else {
                        recipeSelection
                    }
                }
                .padding()
            }
            .background(DougTheme.warmCream)
            .navigationTitle("Schedule")
            .sheet(isPresented: $showConfig) {
                ScheduleConfigSheet(viewModel: viewModel) {
                    viewModel.startBake(modelContext: availabilities.first != nil
                        ? getModelContext()
                        : getModelContext())
                    showConfig = false
                }
            }
        }
    }

    @Environment(\.modelContext) private var modelContext

    private func getModelContext() -> ModelContext {
        modelContext
    }

    private var recipeSelection: some View {
        VStack(spacing: 16) {
            ForEach(RecipeBook.all) { recipe in
                RecipeCard(recipe: recipe, isSelected: recipe.id == viewModel.selectedRecipeID) {
                    viewModel.selectedRecipeID = recipe.id
                }
            }

            Button {
                viewModel.buildPreview(
                    availability: availabilities.first,
                    windows: Array(windows)
                )
                showConfig = true
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
}

// MARK: - Recipe Card

private struct RecipeCard: View {
    let recipe: Recipe
    let isSelected: Bool
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
            .background(
                Color(.systemBackground),
                in: .rect(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active Bake Section

private struct ActiveBakeSection: View {
    let schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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

            ForEach(schedule.steps.sorted(by: { $0.sequenceIndex < $1.sequenceIndex })) { step in
                StepTimelineRow(step: step)
            }
        }
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
                Text(step.stepType.label)
                    .font(.subheadline.bold())

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
