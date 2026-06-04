import SwiftUI

/// A 1–5 star rating. Read-only when `onTap` is nil, interactive otherwise.
struct StarRatingView: View {
    let rating: Int
    var max: Int = 5
    var font: Font = .title3
    var onTap: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1 ... max, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(font)
                    .foregroundStyle(value <= rating ? DougTheme.crustGold : Color.secondary)
                    .contentShape(.rect)
                    .onTapGesture { onTap?(value) }
                    .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                    .accessibilityAddTraits(onTap == nil ? [] : .isButton)
            }
        }
    }
}

/// A labelled 1–5 selector for a qualitative trait (e.g. crumb tight→open).
/// Read-only when `onSelect` is nil.
struct ScoreSelector: View {
    let title: String
    let lowLabel: String
    let highLabel: String
    let score: Int
    var onSelect: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 10) {
                ForEach(1 ... 5, id: \.self) { value in
                    Circle()
                        .fill(value <= score ? DougTheme.sourdoughBrown : Color(.tertiarySystemFill))
                        .frame(width: 22, height: 22)
                        .overlay {
                            if value <= score {
                                Circle().stroke(DougTheme.sourdoughBrown, lineWidth: 1)
                            }
                        }
                        .contentShape(.circle)
                        .onTapGesture { onSelect?(value) }
                        .accessibilityLabel("\(title): \(value) of 5")
                        .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
                }
            }
            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
