import SwiftData
import SwiftUI

/// Journal of finished bakes. Lists completed schedules newest-first; each links
/// to a `BakeDetailView` with photos, reflection, and fermentation stats.
struct HistoryTab: View {
    @Query(
        filter: #Predicate<Schedule> { $0.status == "complete" },
        sort: \Schedule.completedAt,
        order: .reverse
    )
    private var bakes: [Schedule]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if bakes.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Schedule.self) { schedule in
                BakeDetailView(schedule: schedule)
            }
            .background(DougTheme.warmCream.ignoresSafeArea())
        }
    }

    private var list: some View {
        List {
            ForEach(bakes) { schedule in
                NavigationLink(value: schedule) {
                    BakeHistoryRow(schedule: schedule)
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No bakes yet", systemImage: "book.closed")
        } description: {
            Text("Finish a bake to save it here — with photos, a rating, and notes you can look back on.")
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(bakes[index])
        }
    }
}

/// One row in the History list: thumbnail, recipe name, completion date, rating.
struct BakeHistoryRow: View {
    let schedule: Schedule

    private var profile: BakeFermentationProfile? {
        schedule.fermentationProfile
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.recipe.name)
                    .font(.headline)
                if let date = schedule.completedAt {
                    Text(date, format: .dateTime.weekday().day().month())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let rating = profile?.rating, rating > 0 {
                    StarRatingView(rating: rating, font: .caption)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = profile?.orderedPhotos.first?.imageData,
           let image = UIImage(data: data)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "birthday.cake")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
