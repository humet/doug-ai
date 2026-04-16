import SwiftUI
import SwiftData

struct StarterTab: View {
    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    var body: some View {
        NavigationStack {
            List {
                if feedLogs.isEmpty {
                    ContentUnavailableView(
                        "No Feeds Logged",
                        systemImage: "bubbles.and.sparkles",
                        description: Text("Log your first starter feed to start tracking.")
                    )
                } else {
                    ForEach(feedLogs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.ratioDescription)
                                .font(.headline)
                            HStack {
                                Text(log.flourType)
                                Spacer()
                                Text(log.timestamp, style: .relative)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Starter")
        }
    }
}

#Preview {
    StarterTab()
        .modelContainer(for: StarterFeedLog.self, inMemory: true)
}
