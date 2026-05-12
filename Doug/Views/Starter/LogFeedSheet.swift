import SwiftData
import SwiftUI

struct LogFeedSheet: View {
    @Bindable var viewModel: StarterViewModel
    let modelContext: ModelContext
    var profile: StarterProfile?

    @Environment(\.dismiss) private var dismiss

    @State private var showRatioCustomisation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Time") {
                    DatePicker("Fed at", selection: $viewModel.feedTimestamp, in: ...Date())
                }

                Section {
                    HStack {
                        Text("Keep")
                        Spacer()
                        TextField("10", text: $viewModel.logFeedStarterGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    if let grams = starterGrams {
                        let flourGrams = grams * Double(viewModel.feedRatioFlour) / Double(viewModel.feedRatioStarter)
                        let waterGrams = grams * Double(viewModel.feedRatioWater) / Double(viewModel.feedRatioStarter)
                        HStack {
                            Text("Flour")
                            Spacer()
                            Text("\(gramString(flourGrams)) g")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Water")
                            Spacer()
                            Text("\(gramString(waterGrams)) g")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Total")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(gramString(grams + flourGrams + waterGrams)) g")
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Ratio")
                        Spacer()
                        Text("\(viewModel.feedRatioStarter):\(viewModel.feedRatioFlour):\(viewModel.feedRatioWater)")
                            .foregroundStyle(.secondary)
                        Button {
                            showRatioCustomisation.toggle()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showRatioCustomisation ? 90 : 0))
                        }
                        .buttonStyle(.plain)
                    }

                    if showRatioCustomisation {
                        Stepper(
                            "Starter: \(viewModel.feedRatioStarter)",
                            value: $viewModel.feedRatioStarter,
                            in: 1 ... 10
                        )
                        Stepper("Flour: \(viewModel.feedRatioFlour)", value: $viewModel.feedRatioFlour, in: 1 ... 20)
                        Stepper("Water: \(viewModel.feedRatioWater)", value: $viewModel.feedRatioWater, in: 1 ... 20)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    Text(ratioGuidance)
                }

                Section("Details") {
                    HStack {
                        Text("Flour")
                        Spacer()
                        TextField("e.g. white, 50/50 white/rye", text: $viewModel.feedFlourType)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    if isActivationFeed {
                        HStack {
                            Text("Kitchen temp")
                            Spacer()
                            Text("\(Int(viewModel.feedKitchenTemp))°C")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $viewModel.feedKitchenTemp, in: 16 ... 32, step: 1)
                    }
                }

                howToFeedSection
            }
            .navigationTitle("Log Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.logFeed(modelContext: modelContext, profile: profile)
                    }
                }
            }
            .onAppear {
                if isActivationFeed {
                    viewModel.feedRatioFlour = 5
                    viewModel.feedRatioWater = 5
                } else {
                    viewModel.feedRatioFlour = 1
                    viewModel.feedRatioWater = 1
                }
                if viewModel.logFeedStarterGrams.isEmpty {
                    viewModel.logFeedStarterGrams = "10"
                }
            }
        }
    }

    private var isActivationFeed: Bool {
        profile?.starterLifecycleState == .activating
    }

    private var ratioGuidance: String {
        if isActivationFeed {
            return "1:5:5 gives a strong, predictable rise over ~5–6 hours. Use 1:3:3 for a faster peak (~3–4h), or 1:10:10 to time an overnight feed."
        }
        return "1:1:1 is enough food for 1–2 weeks in the fridge with minimal waste. Use 1:2:2 if storing for longer."
    }

    @ViewBuilder
    private var howToFeedSection: some View {
        let retain = starterGrams ?? 10
        let flour = retain * Double(viewModel.feedRatioFlour) / Double(viewModel.feedRatioStarter)
        let water = retain * Double(viewModel.feedRatioWater) / Double(viewModel.feedRatioStarter)

        let feedKind: FeedStepKind = isActivationFeed ? .activation : .maintenance

        let instruction = FeedInstructions.instruction(
            for: FeedInstructionInput(
                retainGrams: retain,
                addFlourGrams: flour,
                addWaterGrams: water,
                flourType: viewModel.feedFlourType,
                kitchenTempC: viewModel.feedKitchenTemp,
                expectedPeakMinutes: 300,
                kind: feedKind,
                hadHooch: false,
                neglect: nil
            )
        )

        Section {
            ForEach(Array(instruction.steps.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(idx + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(line)
                        .font(.caption)
                }
            }
        } header: {
            Text("How to feed")
        }
    }

    private var starterGrams: Double? {
        let trimmed = viewModel.logFeedStarterGrams.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let v = Double(trimmed), v > 0 else { return nil }
        return v
    }

    private func gramString(_ grams: Double) -> String {
        let rounded = grams.rounded()
        if abs(rounded - grams) < 0.05 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", grams)
    }
}
