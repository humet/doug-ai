import SwiftUI

/// Banner shown during an active bake when cascaded step times push
/// hands-on steps into the user's unavailable windows.
struct ConflictBanner: View {
    let conflicts: [ActiveConflict]
    var onOpenCoach: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Schedule conflict")
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(conflicts) { conflict in
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        "\(conflict.stepLabel) now at \(conflict.scheduledStart, style: .time) – \(conflict.scheduledEnd, style: .time)"
                    )
                    .font(.caption)
                }
            }

            Text(
                "Some hands-on steps have moved outside your available hours. Try adjusting flexible step durations or picking a different target time."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if onOpenCoach != nil {
                let stepList = conflicts.map(\.stepLabel).joined(separator: ", ")
                Button {
                    onOpenCoach?(
                        "These steps have moved into unavailable time: \(stepList). Can you adjust the schedule?"
                    )
                } label: {
                    Label("Fix this", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .adaptiveGlassButtonStyle()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14))
    }
}
