import SwiftUI

/// Banner shown during an active bake when cascaded step times push
/// hands-on steps into the user's unavailable windows.
struct ConflictBanner: View {
    let conflicts: [ActiveConflict]

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
                    Text("\(conflict.stepLabel) now at \(conflict.scheduledStart, style: .time) – \(conflict.scheduledEnd, style: .time)")
                        .font(.caption)
                }
            }

            Text("Some hands-on steps have moved outside your available hours. Try extending cold retard or adjusting step times to shift them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14))
    }
}
