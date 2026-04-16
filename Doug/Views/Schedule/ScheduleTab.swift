import SwiftUI

struct ScheduleTab: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(RecipeBook.all) { recipe in
                        RecipeCard(recipe: recipe)
                    }
                }
                .padding()
            }
            .background(DougTheme.warmCream)
            .navigationTitle("Schedule")
        }
    }
}

private struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recipe.name)
                    .font(.headline)
                Spacer()
                Text("\(recipe.hydrationPercent)% hydration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(recipe.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Label(recipe.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                    .font(.caption)
                Spacer()
                Label("\(recipe.approximateTotalHours.lowerBound)–\(recipe.approximateTotalHours.upperBound)h", systemImage: "clock")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 12))
    }
}

#Preview {
    ScheduleTab()
}
