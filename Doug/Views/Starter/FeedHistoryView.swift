import SwiftData
import SwiftUI

/// Full feed history, grouped by month. The Starter tab shows only the most
/// recent feeds; this screen holds the rest.
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

    private var monthGroups: [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: feedLogs) { log in
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
            ForEach(monthGroups) { group in
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
                        feedLogs: Array(feedLogs)
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
