import SwiftData
import SwiftUI

/// Small sheet for confirming when a feed peaked. Defaults to now, supports
/// backdating, and offers an "it peaked while I slept" estimate that records
/// the peak without polluting the starter's time-to-peak averages.
struct MarkPeakSheet: View {
    let log: StarterFeedLog
    let viewModel: StarterViewModel
    var profile: StarterProfile?
    let allLogs: [StarterFeedLog]

    @Environment(\.dismiss) private var dismiss
    @State private var peakDate = Date()

    private var estimatedPeak: Date {
        viewModel.estimatedPeakDate(for: log, profile: profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Peaked at",
                        selection: $peakDate,
                        in: log.timestamp ... Date()
                    )
                } footer: {
                    let fedAt = log.timestamp.formatted(.dateTime.weekday(.wide).hour().minute())
                    Text("Fed \(fedAt). Backdate this if you spotted the peak a while ago.")
                }

                Section {
                    Button {
                        viewModel.markPeak(
                            for: log,
                            at: estimatedPeak,
                            estimated: true,
                            profile: profile,
                            allLogs: allLogs
                        )
                        viewModel.markPeakTarget = nil
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("It peaked while I slept", systemImage: "moon.zzz")
                                .font(.subheadline.weight(.medium))
                            let estimateText = estimatedPeak.formatted(.dateTime.weekday(.wide).hour().minute())
                            Text(
                                "We'll estimate \(estimateText) from your starter's usual rise. "
                                    + "Estimates never affect your averages."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Mark Peak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.markPeakTarget = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark Peak") {
                        viewModel.markPeak(
                            for: log,
                            at: peakDate,
                            profile: profile,
                            allLogs: allLogs
                        )
                        viewModel.markPeakTarget = nil
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
