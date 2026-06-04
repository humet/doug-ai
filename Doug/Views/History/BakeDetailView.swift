import SwiftData
import SwiftUI

/// Detail for one finished bake: photo gallery, reflection (rating, tags, notes),
/// fermentation stats, the temperature/degree-hour chart, and the step timeline.
/// Offers "Bake again" to re-plan the same recipe.
struct BakeDetailView: View {
    let schedule: Schedule

    @State private var router = NotificationRouter.shared

    private var profile: BakeFermentationProfile? {
        schedule.fermentationProfile
    }

    private var recipe: Recipe {
        schedule.recipe
    }

    private var recipeID: RecipeID {
        RecipeID(rawValue: schedule.recipeID)!
    }

    private var topLevelSteps: [ScheduleStep] {
        schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    private var hasTags: Bool {
        guard let p = profile else { return false }
        return p.crumbOpenness > 0 || p.crustColor > 0 || p.sourness > 0 || p.ovenSpring > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                gallery
                header
                if let profile, profile.rating > 0 { ratingSection(profile) }
                if hasTags, let profile { tagsSection(profile) }
                if let note = profile?.outcomeNote, !note.isEmpty { notesSection(note) }
                if let profile { statsSection(profile) }
                if !schedule.temperatureReadings.isEmpty { chartSection }
                if !topLevelSteps.isEmpty { timelineSection }
            }
            .padding()
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(DougTheme.warmCream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            bakeAgainButton.padding()
        }
    }

    // MARK: - Gallery

    @ViewBuilder
    private var gallery: some View {
        let photos = profile?.orderedPhotos ?? []
        if !photos.isEmpty {
            TabView {
                ForEach(photos) { photo in
                    if let image = UIImage(data: photo.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
            .tabViewStyle(.page)
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: 16))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.name)
                .font(.title2.bold())
            if let date = schedule.completedAt {
                Label(
                    date.formatted(date: .complete, time: .shortened),
                    systemImage: "checkmark.seal"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ratingSection(_ profile: BakeFermentationProfile) -> some View {
        card {
            HStack {
                Text("Rating")
                    .font(.headline)
                Spacer()
                StarRatingView(rating: profile.rating)
            }
        }
    }

    private func tagsSection(_ profile: BakeFermentationProfile) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("How it turned out")
                    .font(.headline)
                if profile.crumbOpenness > 0 {
                    ScoreSelector(title: "Crumb", lowLabel: "Tight", highLabel: "Open", score: profile.crumbOpenness)
                }
                if profile.crustColor > 0 {
                    ScoreSelector(title: "Crust", lowLabel: "Pale", highLabel: "Dark", score: profile.crustColor)
                }
                if profile.sourness > 0 {
                    ScoreSelector(title: "Sourness", lowLabel: "Mild", highLabel: "Tangy", score: profile.sourness)
                }
                if profile.ovenSpring > 0 {
                    ScoreSelector(title: "Oven spring", lowLabel: "Flat", highLabel: "Big", score: profile.ovenSpring)
                }
            }
        }
    }

    private func notesSection(_ note: String) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.headline)
                Text(note)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statsSection(_ profile: BakeFermentationProfile) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fermentation")
                    .font(.headline)
                statRow(
                    "Degree-hours",
                    String(format: "%.0f / %.0f target", profile.finalDegreeHours, profile.targetDegreeHoursUsed)
                )
                statRow("Kitchen temp", String(format: "%.0f°C", profile.kitchenTemperatureCelsius))
                statRow("Initial mix temp", String(format: "%.1f°C", profile.initialMixTemp))
            }
        }
    }

    private var chartSection: some View {
        DegreeHoursChartView(
            readings: schedule.temperatureReadings,
            targetDegreeHours: recipe.degreeHourTarget
        )
    }

    private var timelineSection: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Timeline")
                    .font(.headline)
                ForEach(topLevelSteps) { step in
                    HStack {
                        Text(step.stepType.label)
                            .font(.subheadline)
                        Spacer()
                        Text(step.actualEndTime ?? step.computedEndTime, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var bakeAgainButton: some View {
        Button {
            router.requestPlanBake(recipeID: recipeID)
        } label: {
            Label("Bake again", systemImage: "arrow.clockwise")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .adaptiveGlassButtonStyle(prominent: true)
    }

    // MARK: - Helpers

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DougTheme.cardBackground, in: .rect(cornerRadius: 16))
    }
}
