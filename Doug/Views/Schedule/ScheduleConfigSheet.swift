import SwiftData
import SwiftUI

struct ScheduleConfigSheet: View {
    @Bindable var viewModel: ScheduleViewModel
    let onStartBake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]
    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label(viewModel.selectedRecipe.name, systemImage: "book")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.selectedRecipe.hydrationPercent)%")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recipe")
                }

                Section {
                    DatePicker(
                        "Bread ready by",
                        selection: $viewModel.targetDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Target Time")
                }

                Section {
                    HStack {
                        Text("Kitchen temperature")
                        Spacer()
                        Text("\(Int(viewModel.kitchenTemperature))°C")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $viewModel.kitchenTemperature,
                        in: 16 ... 32,
                        step: 1
                    ) {
                        Text("Temperature")
                    }
                    .onChange(of: viewModel.kitchenTemperature) {
                        rebuildPreview()
                    }
                } header: {
                    Text("Temperature")
                }

                if let ctx = viewModel.detectedLevain {
                    Section {
                        Toggle(isOn: $viewModel.useActiveLevain) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Use active levain")
                                Text(levainSummary(ctx))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: viewModel.useActiveLevain) {
                            rebuildPreview()
                        }
                    } header: {
                        Text("Levain")
                    }
                }

                if !viewModel.previewSteps.isEmpty {
                    Section {
                        ForEach(viewModel.previewSteps) { step in
                            PreviewStepRow(step: step)
                        }
                    } header: {
                        Text("Schedule Preview")
                    }
                }

                if let conflict = viewModel.conflict {
                    Section {
                        Label(conflict.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } header: {
                        Text("Conflict")
                    }
                }
            }
            .navigationTitle("Plan Your Bake")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Bake") {
                        onStartBake()
                    }
                    .disabled(viewModel.previewSteps.isEmpty)
                }
            }
            .onAppear {
                rebuildPreview()
            }
            .onChange(of: viewModel.targetDate) {
                rebuildPreview()
            }
        }
    }

    private func rebuildPreview() {
        viewModel.buildPreview(
            availability: availabilities.first,
            windows: Array(windows),
            feedLogs: Array(feedLogs)
        )
    }

    private func levainSummary(_ ctx: LevainContext) -> String {
        let elapsed = Int(ctx.elapsedMinutes())
        let remaining = Int(ctx.remainingMinutes())

        let elapsedText: String
        if elapsed >= 60 {
            let h = elapsed / 60
            let m = elapsed % 60
            elapsedText = m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            elapsedText = "\(elapsed)m"
        }

        if remaining <= 0 {
            return "Fed \(elapsedText) ago — likely peaked"
        }

        let remainingText: String
        if remaining >= 60 {
            let h = remaining / 60
            let m = remaining % 60
            remainingText = m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            remainingText = "\(remaining)m"
        }

        return "Fed \(elapsedText) ago — ~\(remainingText) remaining"
    }
}

private struct PreviewStepRow: View {
    let step: ScheduledStep

    private var isLevainInProgress: Bool {
        step.levainElapsedMinutes != nil
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(step.label)
                        .font(.subheadline)
                    if isLevainInProgress {
                        Text("in progress")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green, in: .capsule)
                    }
                }
                Text(step.startTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Text(formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            classificationBadge
        }
    }

    private var formattedDuration: String {
        let minutes = Int(step.durationMinutes)
        if isLevainInProgress {
            if minutes <= 0 { return "ready" }
            if minutes >= 60 {
                let hours = minutes / 60
                let mins = minutes % 60
                return mins > 0 ? "~\(hours)h \(mins)m left" : "~\(hours)h left"
            }
            return "~\(minutes)m left"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    @ViewBuilder
    private var classificationBadge: some View {
        switch step.classification {
        case .handsOn:
            Image(systemName: "hand.raised")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .passiveFlexible:
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundStyle(.green)
        case .passiveFixed:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
