import SwiftUI

struct CalculatorTab: View {
    @State private var flourGrams: Double = 500
    @State private var waterGrams: Double = 350
    @State private var levainGrams: Double = 100
    @State private var levainHydrationPercent: Double = 100
    @State private var saltGrams: Double = 10

    private var trueHydration: Double {
        let levainFlour = levainGrams / (1 + levainHydrationPercent / 100)
        let levainWater = levainGrams - levainFlour
        let totalFlour = flourGrams + levainFlour
        let totalWater = waterGrams + levainWater
        guard totalFlour > 0 else { return 0 }
        return (totalWater / totalFlour) * 100
    }

    private var doughHydration: Double {
        guard flourGrams > 0 else { return 0 }
        return (waterGrams / flourGrams) * 100
    }

    private var totalDoughWeight: Double {
        flourGrams + waterGrams + levainGrams + saltGrams
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredients") {
                    ingredientRow("Flour", value: $flourGrams, unit: "g")
                    ingredientRow("Water", value: $waterGrams, unit: "g")
                    ingredientRow("Levain", value: $levainGrams, unit: "g")
                    ingredientRow("Levain hydration", value: $levainHydrationPercent, unit: "%")
                    ingredientRow("Salt", value: $saltGrams, unit: "g")
                }

                Section("Results") {
                    resultRow("Dough hydration", value: String(format: "%.1f%%", doughHydration))
                    resultRow("True hydration", value: String(format: "%.1f%%", trueHydration))
                    resultRow("Total dough weight", value: String(format: "%.0fg", totalDoughWeight))
                }
            }
            .navigationTitle("Calculator")
        }
    }

    private func ingredientRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
        }
    }

    private func resultRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    CalculatorTab()
}
