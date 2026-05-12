import SwiftData
import SwiftUI

struct PostBakeSheet: View {
    @Bindable var viewModel: StarterViewModel
    let modelContext: ModelContext
    var profile: StarterProfile?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Feed your leftover starter and put it back in the fridge. No need to watch for a peak.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Ratio") {
                    Stepper("Starter: \(viewModel.feedRatioStarter)", value: $viewModel.feedRatioStarter, in: 1 ... 10)
                    Stepper("Flour: \(viewModel.feedRatioFlour)", value: $viewModel.feedRatioFlour, in: 1 ... 20)
                    Stepper("Water: \(viewModel.feedRatioWater)", value: $viewModel.feedRatioWater, in: 1 ... 20)
                }

                Section {
                    HStack {
                        Text("Starter amount")
                        Spacer()
                        TextField("optional", text: $viewModel.logFeedStarterGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Amount")
                }

                Section("Details") {
                    Picker("Flour type", selection: $viewModel.feedFlourType) {
                        Text("White").tag("white")
                        Text("Whole Wheat").tag("whole wheat")
                        Text("Rye").tag("rye")
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
        }
    }
}
