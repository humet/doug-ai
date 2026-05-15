import SwiftData
import SwiftUI

struct PlanAheadSection: View {
    let profile: StarterProfile?
    let feedLogs: [StarterFeedLog]
    let availabilities: [UserAvailability]
    let windows: [UnavailableWindow]

    @State private var planAheadDate: Date?
    @State private var planAheadRecipeID: RecipeID = .countryLoaf
    @State private var planAheadReminderSet = false
    @State private var estimateResult: PlanAheadEstimator.Result?

    private var estimateInput: PlanAheadInput? {
        guard let target = planAheadDate else { return nil }
        return PlanAheadInput(
            recipeID: planAheadRecipeID,
            target: target,
            kitchenTemp: feedLogs.first?.kitchenTemperatureCelsius ?? 22.0,
            hasAvailability: availabilities.first != nil,
            windowCount: windows.filter(\.isActive).count,
            activePeakAverage: profile?.activePeakAverageMinutes,
            storageType: profile?.starterStorageType ?? .fridge
        )
    }

    var body: some View {
        Section {
            Picker("Recipe", selection: $planAheadRecipeID) {
                ForEach(RecipeBook.all) { recipe in
                    Text(recipe.name).tag(recipe.id)
                }
            }

            DatePicker(
                "Bread ready by",
                selection: Binding(
                    get: { planAheadDate ?? defaultPlanAheadDate() },
                    set: {
                        planAheadDate = $0
                        planAheadReminderSet = false
                    }
                ),
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )

            if planAheadDate != nil {
                estimateContent
            }
        } header: {
            Text("Plan Ahead")
        } footer: {
            footerText
        }
        .task(id: estimateInput) {
            guard let input = estimateInput else {
                estimateResult = nil
                return
            }
            let avail = availabilities.first.map { AvailabilityInput(from: $0) }
            let windowInputs = windows.map { WindowInput(from: $0) }
            let peakProfile: StarterPeakProfile? = feedLogs.isEmpty ? nil
                : StarterPeakProfile(
                    feedLogs: feedLogs.map { FeedLogInput(from: $0) },
                    intentFilter: .activation
                )
            estimateResult = PlanAheadEstimator.estimate(
                recipe: RecipeBook.recipe(for: input.recipeID),
                targetBreadReadyTime: input.target,
                kitchenTemperatureCelsius: input.kitchenTemp,
                availability: avail,
                unavailableWindows: windowInputs,
                peakProfile: peakProfile,
                activePeakAverageMinutes: input.activePeakAverage,
                storageType: input.storageType
            )
            planAheadReminderSet = false
        }
    }

    // MARK: - Estimate Content

    @ViewBuilder
    private var estimateContent: some View {
        switch estimateResult {
        case let .feasible(estimate), let .noAvailabilityConfigured(estimate):
            estimateRow(estimate: estimate)
            reminderButton(estimate: estimate)

        case let .conflict(message, suggestedTime):
            conflictRow(message: message, suggestedTime: suggestedTime)

        case nil:
            EmptyView()
        }
    }

    private func estimateRow(estimate: PlanAheadEstimator.Estimate) -> some View {
        HStack {
            Label("Take it out by", systemImage: "clock")
            Spacer()
            Text(estimate.activateBy.formatted(.dateTime.weekday(.wide).hour().minute()))
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func reminderButton(estimate: PlanAheadEstimator.Estimate) -> some View {
        let recipe = RecipeBook.recipe(for: planAheadRecipeID)
        if !planAheadReminderSet {
            Button {
                Task {
                    await NotificationService.shared.scheduleStarterFeedReminder(
                        at: estimate.activateBy,
                        context: "Time to take your starter out for your \(recipe.name) bake."
                    )
                    planAheadReminderSet = true
                }
            } label: {
                Label("Remind Me", systemImage: "bell")
            }
        } else {
            Label("Reminder set", systemImage: "bell.fill")
                .foregroundStyle(.green)
        }
    }

    private func conflictRow(message: String, suggestedTime: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            if let suggestedTime {
                Text("Try \(suggestedTime.formatted(.dateTime.weekday(.wide).hour().minute())) instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var footerText: some View {
        switch estimateResult {
        case .noAvailabilityConfigured:
            Text("Set your available hours in Settings for a more accurate estimate.")
        case .feasible:
            Text("Accounts for your sleep hours and unavailable windows.")
        default:
            Text("Pick when you want bread ready and we'll tell you when to activate your starter.")
        }
    }

    // MARK: - Helpers

    private func defaultPlanAheadDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// MARK: - Input Identity

private struct PlanAheadInput: Hashable {
    let recipeID: RecipeID
    let target: Date
    let kitchenTemp: Double
    let hasAvailability: Bool
    let windowCount: Int
    let activePeakAverage: Double?
    let storageType: StarterStorageType
}
