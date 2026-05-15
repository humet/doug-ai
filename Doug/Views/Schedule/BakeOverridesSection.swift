import SwiftData
import SwiftUI

struct BakeOverridesSection: View {
    let windows: [UnavailableWindow]
    @Binding var disabledIDs: Set<PersistentIdentifier>
    let onChange: () -> Void

    @State private var isExpanded = true

    var body: some View {
        Section("Availability for this bake", isExpanded: $isExpanded) {
            ForEach(windows) { window in
                Toggle(isOn: toggleBinding(for: window)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.name)
                            .font(.subheadline)
                        Text(windowTimeDescription(window))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func toggleBinding(for window: UnavailableWindow) -> Binding<Bool> {
        Binding(
            get: { !disabledIDs.contains(window.persistentModelID) },
            set: { isActive in
                if isActive {
                    disabledIDs.remove(window.persistentModelID)
                } else {
                    disabledIDs.insert(window.persistentModelID)
                }
                onChange()
            }
        )
    }

    private func windowTimeDescription(_ window: UnavailableWindow) -> String {
        let start = formatTime(hour: window.startHour, minute: window.startMinute)
        let end = formatTime(hour: window.endHour, minute: window.endMinute)
        var desc = "\(start) – \(end)"
        if window.isRecurring {
            let dayNames = window.daysOfWeek.compactMap { shortDayName($0) }
            if !dayNames.isEmpty {
                desc += ", \(dayNames.joined(separator: ", "))"
            }
        }
        return desc
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let calendar = Calendar.current
        let comps = DateComponents(hour: hour, minute: minute)
        guard let date = calendar.date(from: comps) else {
            return "\(hour):\(String(format: "%02d", minute))"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func shortDayName(_ weekday: Int) -> String? {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return nil }
        return symbols[weekday - 1]
    }
}
