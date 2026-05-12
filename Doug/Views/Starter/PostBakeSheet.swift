import SwiftData
import SwiftUI

struct PostBakeSheet: View {
    @Bindable var viewModel: StarterViewModel
    let modelContext: ModelContext
    var profile: StarterProfile?

    @Environment(\.dismiss) private var dismiss
    @State private var showRatioCustomisation = false

    private var starterGrams: Double? {
        let trimmed = viewModel.logFeedStarterGrams.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let v = Double(trimmed), v > 0 else { return nil }
        return v
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Feed your leftover starter and put it back in the fridge. No need to watch for a peak.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                        Stepper("Starter: \(viewModel.feedRatioStarter)", value: $viewModel.feedRatioStarter, in: 1 ... 10)
                        Stepper("Flour: \(viewModel.feedRatioFlour)", value: $viewModel.feedRatioFlour, in: 1 ... 20)
                        Stepper("Water: \(viewModel.feedRatioWater)", value: $viewModel.feedRatioWater, in: 1 ... 20)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    Text("1:1:1 is enough food for 1–2 weeks in the fridge with minimal waste. Use 1:2:2 if storing for longer.")
                }

                Section("Details") {
                    HStack {
                        Text("Flour")
                        Spacer()
                        TextField("e.g. white, 50/50 white/rye", text: $viewModel.feedFlourType)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Feed & Refrigerate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let profile {
                            viewModel.feedAndRefrigerate(profile: profile, modelContext: modelContext)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.feedRatioFlour = 1
                viewModel.feedRatioWater = 1
                if viewModel.logFeedStarterGrams.isEmpty {
                    viewModel.logFeedStarterGrams = "10"
                }
            }
        }
    }

    private func gramString(_ grams: Double) -> String {
        let rounded = grams.rounded()
        if abs(rounded - grams) < 0.05 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", grams)
    }
}
