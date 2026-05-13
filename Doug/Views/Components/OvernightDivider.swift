import SwiftUI

struct OvernightDivider: View {
    let from: Date
    let to: Date

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDate(to, inSameDayAs: from.addingTimeInterval(86400)) {
            return "Overnight"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: to)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.zzz.fill")
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .listRowBackground(Color.clear)
    }
}
