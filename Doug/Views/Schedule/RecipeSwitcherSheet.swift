import SwiftData
import SwiftUI

struct RecipeSwitcherSheet: View {
    let viewModel: ScheduleViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]
    @Query private var profiles: [StarterProfile]
    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    var body: some View {
        NavigationStack {
            List {
                if viewModel.detectedLevain != nil {
                    Section {
                        Label(
                            "Your levain is still rising — the new recipe will use it.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Choose a recipe") {
                    let otherRecipes = RecipeBook.all.filter { $0.id != viewModel.selectedRecipeID }
                    ForEach(otherRecipes) { recipe in
                        RecipeSwitcherRow(recipe: recipe) {
                            switchTo(recipe.id)
                        }
                    }
                }
            }
            .navigationTitle("Switch Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func hasActiveLevain() -> Bool {
        viewModel.detectedLevain != nil
    }

    private func switchTo(_ recipeID: RecipeID) {
        withAnimation(.smooth) {
            viewModel.switchRecipe(
                to: recipeID,
                availability: availabilities.first,
                windows: Array(windows),
                feedLogs: Array(feedLogs),
                starterProfile: profiles.first,
                modelContext: modelContext
            )
        }
        if viewModel.conflict == nil, !viewModel.previewSteps.isEmpty {
            viewModel.startBake(modelContext: modelContext)
        }
        dismiss()
    }
}

private struct RecipeSwitcherRow: View {
    let recipe: Recipe
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                        .font(.subheadline.weight(.medium))
                    let hours = recipe.approximateTotalHours
                    Text("\(recipe.hydrationPercent)% hydration · \(hours.lowerBound)–\(hours.upperBound)h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }
}
