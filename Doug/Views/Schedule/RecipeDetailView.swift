import SwiftData
import SwiftUI

/// Pre-bake "learn the recipe" view. Pushed from a recipe card on the Schedule tab,
/// or presented as a sheet while a bake is active. Hosts the "Plan this bake" CTA.
struct RecipeDetailView: View {
    let recipe: Recipe
    var showPlanCTA: Bool = true
    var onPlanBake: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                ingredientsSection
                methodSection
                if showPlanCTA {
                    planButton
                }
            }
            .padding()
        }
        .background(DougTheme.warmCream)
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            Text(recipe.name)
                .font(.title.bold())
            Text(recipe.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                heroChip(label: recipe.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                heroChip(label: "\(recipe.hydrationPercent)% hydration", systemImage: "drop")
                heroChip(
                    label: "\(recipe.approximateTotalHours.lowerBound)–\(recipe.approximateTotalHours.upperBound)h",
                    systemImage: "clock"
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)

        if reduceTransparency {
            content.background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        } else {
            content.background(DougTheme.cardBackground, in: .rect(cornerRadius: 16))
        }
    }

    private func heroChip(label: String, systemImage: String) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemBackground), in: .capsule)
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Ingredients")
            IngredientsTableView(ingredients: recipe.ingredients)
            Text("Baker's percentages are shown relative to the main flour weight.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Method

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Method")
            VStack(spacing: 12) {
                ForEach(Array(recipe.method.enumerated()), id: \.offset) { index, step in
                    MethodStepCard(step: step, stepNumber: index + 1)
                }
            }
        }
    }

    // MARK: - Plan Button

    private var planButton: some View {
        Button {
            onPlanBake?()
            dismiss()
        } label: {
            Label("Plan this bake", systemImage: "calendar.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .adaptiveGlassButtonStyle(prominent: true)
        .padding(.top, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: RecipeBook.countryLoaf)
    }
}
