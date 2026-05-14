import SwiftUI

struct InlineFeedEntryView: View {
    @Binding var ratioStarter: Int
    @Binding var ratioFlour: Int
    @Binding var ratioWater: Int
    @Binding var starterGrams: String
    @Binding var kitchenTemp: Double

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "scalemass")
                        .font(.caption)
                    Text("Feed: \(ratioStarter):\(ratioFlour):\(ratioWater)")
                        .font(.caption.weight(.medium))
                    if let grams = Double(starterGrams), grams > 0 {
                        Text("· \(Int(grams))g starter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if expanded {
                VStack(spacing: 10) {
                    HStack {
                        Text("Keep")
                            .font(.caption)
                        Spacer()
                        TextField("10", text: $starterGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 60)
                            .font(.caption)
                        Text("g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    gramsBreakdown

                    HStack {
                        Text("Ratio")
                            .font(.caption)
                        Spacer()
                        Stepper(
                            "\(ratioStarter):\(ratioFlour):\(ratioWater)",
                            value: $ratioFlour,
                            in: 1 ... 20
                        )
                        .font(.caption)
                    }

                    HStack {
                        Text("Kitchen")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(kitchenTemp))°C")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper("", value: $kitchenTemp, in: 15 ... 35, step: 1)
                            .labelsHidden()
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var gramsBreakdown: some View {
        if let grams = Double(starterGrams), grams > 0 {
            let flourGrams = grams * Double(ratioFlour) / Double(ratioStarter)
            let waterGrams = grams * Double(ratioWater) / Double(ratioStarter)
            HStack {
                HStack(spacing: 4) {
                    Text("Flour")
                        .font(.caption)
                    Text("\(Int(flourGrams))g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Water")
                        .font(.caption)
                    Text("\(Int(waterGrams))g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Total")
                        .font(.caption.weight(.medium))
                    Text("\(Int(grams + flourGrams + waterGrams))g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
