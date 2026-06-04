import SwiftUI

/// Renders a recipe's ingredients with grams and baker's percentages in a single table.
struct IngredientsTableView: View {
    let ingredients: Ingredients

    private var percentages: BakersPercentages {
        HydrationCalculator.bakersPercentages(
            flourGrams: ingredients.flourGrams,
            waterGrams: ingredients.waterGrams,
            levainGrams: ingredients.levainGrams,
            saltGrams: ingredients.saltGrams,
            extras: ingredients.extras.map { ($0.name, $0.grams) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            let flourRows = ingredients.flourBreakdownRows
            ForEach(Array(flourRows.enumerated()), id: \.offset) { index, flour in
                if index > 0 { Divider() }
                // Baker's percentage uses total flour as the 100% base, so each
                // flour's share of the total is also its baker's percentage.
                row(name: flour.name, grams: flour.grams, percent: flour.grams / ingredients.flourGrams * 100)
            }
            Divider()
            row(name: "Water", grams: ingredients.waterGrams, percent: percentages.water)
            Divider()
            row(name: "Levain", grams: ingredients.levainGrams, percent: percentages.levain)
            Divider()
            row(name: "Salt", grams: ingredients.saltGrams, percent: percentages.salt)

            ForEach(Array(ingredients.extras.enumerated()), id: \.offset) { index, extra in
                Divider()
                row(
                    name: extra.name,
                    grams: extra.grams,
                    percent: percentages.extras[safe: index]?.percent ?? 0,
                    note: extra.note
                )
            }
        }
        .padding(.vertical, 6)
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 14))
    }

    private func row(name: String, grams: Double, percent: Double, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(Int(grams.rounded()))g")
                .font(.subheadline.monospacedDigit())
            Text(String(format: "%.0f%%", percent))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
