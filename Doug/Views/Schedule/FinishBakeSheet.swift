import PhotosUI
import SwiftUI

/// Post-bake reflection. Captures photos, an overall rating, structured crumb/
/// crust/sourness/oven-spring tags, and notes, then either saves them to History
/// or finishes the bake without a reflection. Dismissing (Cancel) leaves the bake
/// active.
struct FinishBakeSheet: View {
    let recipeName: String
    let onSave: (BakeReflection) -> Void
    let onFinishWithoutSaving: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoData: [Data] = []
    @State private var isLoadingPhotos = false

    @State private var rating = 0
    @State private var crumbOpenness = 0
    @State private var crustColor = 0
    @State private var sourness = 0
    @State private var ovenSpring = 0
    @State private var notes = ""

    private var reflection: BakeReflection {
        BakeReflection(
            rating: rating,
            crumbOpenness: crumbOpenness,
            crustColor: crustColor,
            sourness: sourness,
            ovenSpring: ovenSpring,
            notes: notes,
            photoData: photoData
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                ratingSection
                tagsSection
                notesSection
                finishWithoutSavingSection
            }
            .navigationTitle("How did it go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(reflection)
                        dismiss()
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in
                loadPhotos(from: items)
            }
        }
    }

    // MARK: - Sections

    private var photosSection: some View {
        Section {
            if !photoData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photoData.enumerated()), id: \.offset) { _, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(.rect(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 4,
                matching: .images
            ) {
                Label(
                    photoData.isEmpty ? "Add photos" : "Change photos",
                    systemImage: "camera"
                )
            }
            if isLoadingPhotos {
                HStack {
                    ProgressView()
                    Text("Loading photos…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Crumb shot, crust, the whole loaf — up to 4.")
        }
    }

    private var ratingSection: some View {
        Section("Overall") {
            HStack {
                Text(recipeName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                StarRatingView(rating: rating, font: .title2) { rating = $0 }
            }
            .padding(.vertical, 2)
        }
    }

    private var tagsSection: some View {
        Section {
            ScoreSelector(title: "Crumb", lowLabel: "Tight", highLabel: "Open", score: crumbOpenness) {
                crumbOpenness = $0
            }
            ScoreSelector(title: "Crust", lowLabel: "Pale", highLabel: "Dark", score: crustColor) {
                crustColor = $0
            }
            ScoreSelector(title: "Sourness", lowLabel: "Mild", highLabel: "Tangy", score: sourness) {
                sourness = $0
            }
            ScoreSelector(title: "Oven spring", lowLabel: "Flat", highLabel: "Big", score: ovenSpring) {
                ovenSpring = $0
            }
        } header: {
            Text("How it turned out")
        } footer: {
            Text("Optional — tag a few traits so you can compare bakes over time.")
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField(
                "What worked, what you'd change next time…",
                text: $notes,
                axis: .vertical
            )
            .lineLimit(3 ... 8)
        }
    }

    private var finishWithoutSavingSection: some View {
        Section {
            Button("Finish without saving") {
                onFinishWithoutSaving()
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Photo loading

    /// Loads picked items into compressed JPEG bytes, preserving pick order.
    private func loadPhotos(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            photoData = []
            return
        }
        isLoadingPhotos = true
        Task {
            var loaded: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let compressed = Self.compress(data)
                {
                    loaded.append(compressed)
                }
            }
            await MainActor.run {
                photoData = loaded
                isLoadingPhotos = false
            }
        }
    }

    /// Re-encodes to a bounded-size JPEG so the store stays small.
    private static func compress(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
