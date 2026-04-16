import SwiftUI

struct CalculatorTab: View {
    @State private var flourGrams: Double = 500
    @State private var waterGrams: Double = 350
    @State private var levainGrams: Double = 100
    @State private var levainHydrationPercent: Double = 100
    @State private var saltGrams: Double = 10
    @State private var targetWeight: Double = 960

    private var trueHydration: Double {
        HydrationCalculator.trueHydration(
            flourGrams: flourGrams,
            waterGrams: waterGrams,
            levainGrams: levainGrams,
            levainHydrationPercent: levainHydrationPercent
        )
    }

    private var doughHydration: Double {
        HydrationCalculator.doughHydration(flourGrams: flourGrams, waterGrams: waterGrams)
    }

    private var bakersPercentages: BakersPercentages {
        HydrationCalculator.bakersPercentages(
            flourGrams: flourGrams,
            waterGrams: waterGrams,
            levainGrams: levainGrams,
            saltGrams: saltGrams
        )
    }

    private var totalDoughWeight: Double {
        flourGrams + waterGrams + levainGrams + saltGrams
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredients") {
                    ingredientRow("Flour", value: $flourGrams)
                    ingredientRow("Water", value: $waterGrams)
                    ingredientRow("Levain", value: $levainGrams)
                    ingredientRow("Salt", value: $saltGrams)

                    HStack {
                        Text("Levain hydration")
                        Spacer()
                        TextField("100", value: $levainHydrationPercent, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Hydration") {
                    resultRow("Dough hydration", value: String(format: "%.1f%%", doughHydration))
                    resultRow("True hydration", value: String(format: "%.1f%%", trueHydration))
                    resultRow("Total dough weight", value: String(format: "%.0fg", totalDoughWeight))
                }

                Section("Baker's Percentages") {
                    resultRow("Flour", value: "100%")
                    resultRow("Water", value: String(format: "%.1f%%", bakersPercentages.water))
                    resultRow("Levain", value: String(format: "%.1f%%", bakersPercentages.levain))
                    resultRow("Salt", value: String(format: "%.1f%%", bakersPercentages.salt))
                }

                Section("Scale Recipe") {
                    HStack {
                        Text("Target total weight")
                        Spacer()
                        TextField("960", value: $targetWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    Button("Scale to \(Int(targetWeight))g") {
                        applyScale()
                    }
                    .disabled(targetWeight <= 0)
                }
            }
            .navigationTitle("Calculator")
        }
    }

    private func ingredientRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("g")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
        }
    }

    private func resultRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
    }

    private func applyScale() {
        let ingredients = Ingredients(
            flourGrams: flourGrams,
            waterGrams: waterGrams,
            saltGrams: saltGrams,
            levainGrams: levainGrams
        )
        let scaled = RecipeScaler.scale(ingredients: ingredients, toTotalWeight: targetWeight)
        flourGrams = (scaled.flour * 10).rounded() / 10
        waterGrams = (scaled.water * 10).rounded() / 10
        saltGrams = (scaled.salt * 10).rounded() / 10
        levainGrams = (scaled.levain * 10).rounded() / 10
    }
}

#Preview {
    CalculatorTab()
}
