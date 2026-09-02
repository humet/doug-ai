import SwiftData
import SwiftUI

/// Full feed history, grouped by starter and then by month.
///
/// A retired starter's feeds stay readable here — they're a record worth
/// keeping — but they're separated out, because they no longer describe the
/// starter the user has now and they're excluded from its averages.
struct FeedHistoryView: View {
    let viewModel: StarterViewModel
    var profile: StarterProfile?

    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    @Environment(\.modelContext) private var modelContext
    @State private var feedLogToDelete: StarterFeedLog?

    private struct MonthGroup: Identifiable {
        let id: Date
        let title: String
        let logs: [StarterFeedLog]
    }

    private struct GenerationGroup: Identifiable {
        let id: Int
        let title: String?
        let months: [MonthGroup]
    }

    /// The generation the user's current starter belongs to.
    private var liveGeneration: Int {
        profile?.starterGeneration ?? 1
    }

    private var generationGroups: [GenerationGroup] {
        let grouped = Dictionary(grouping: feedLogs, by: \.starterGeneration)
        return grouped
            .sorted { $0.key > $1.key }
            .map { generation, logs in
                GenerationGroup(
                    id: generation,
                    // The current starter needs no label; retired ones do.
                    title: generation >= liveGeneration ? nil : retiredTitle(for: generation),
                    months: monthGroups(for: logs)
                )
            }
    }

    private func retiredTitle(for generation: Int) -> String {
        "Previous starter #\(generation)"
    }

    private func monthGroups(for logs: [StarterFeedLog]) -> [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logs) { log in
            calendar.date(from: calendar.dateComponents([.year, .month], from: log.timestamp)) ?? log.timestamp
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { month, logs in
                MonthGroup(
                    id: month,
                    title: month.formatted(.dateTime.month(.wide).year()),
                    logs: logs.sorted { $0.timestamp > $1.timestamp }
                )
            }
    }

    var body: some View {
        List {
            ForEach(generationGroups) { generation in
                if let title = generation.title {
                    Section {
                        Label(title, systemImage: "archivebox")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Kept for the record. These feeds don't affect your current starter's timings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(generation.months) { group in
                    Section(group.title) {
                        ForEach(group.logs) { log in
                            FeedLogRow(log: log) {
                                viewModel.markPeakTarget = log
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    feedLogToDelete = log
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    viewModel.editingFeedLog = log
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Feed History")
        .alert("Delete Feed Log?", isPresented: Binding(
            get: { feedLogToDelete != nil },
            set: { if !$0 { feedLogToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let log = feedLogToDelete {
                    viewModel.deleteFeedLog(
                        log,
                        modelContext: modelContext,
                        profile: profile,
                        // Averages must only ever be recomputed from the
                        // current starter's readings.
                        feedLogs: viewModel.currentGeneration(Array(feedLogs), profile: profile)
                    )
                }
                feedLogToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                feedLogToDelete = nil
            }
        } message: {
            Text("This feed entry will be permanently removed.")
        }
    }
}
