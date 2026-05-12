import SwiftUI

struct ScheduleAdjustmentBanner: View {
    let adjustment: ScheduleAdjustment
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: adjustment.deltaMinutes < 0
                ? "clock.arrow.trianglehead.counterclockwise.rotate.90"
                : "clock.arrow.2.circlepath")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(adjustment.deltaMinutes < 0
                    ? "Schedule moved earlier"
                    : "Schedule pushed back")
                    .font(.subheadline.weight(.semibold))
                Text("Bulk ferment now ends at \(adjustment.newBulkEndTime, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(.rect)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.12), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schedule adjusted based on temperature readings")
    }
}
