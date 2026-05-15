import SwiftUI

struct TimeSlotGridView: View {
    let slots: [TimeSlot]
    @Binding var selectedTime: Date
    let onSlotInfo: (TimeSlot) -> Void

    private let columns = 4

    var body: some View {
        let rows = stride(from: 0, to: slots.count, by: columns).map { start in
            Array(slots[start ..< min(start + columns, slots.count)])
        }
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { slot in
                        TimeSlotCell(
                            slot: slot,
                            isSelected: Calendar.current.isDate(slot.time, equalTo: selectedTime, toGranularity: .minute)
                        ) {
                            selectedTime = slot.time
                        } onInfo: {
                            onSlotInfo(slot)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTime)
    }
}

struct TimeSlotCell: View {
    let slot: TimeSlot
    let isSelected: Bool
    let onTap: () -> Void
    let onInfo: () -> Void

    private var backgroundColor: Color {
        switch slot.viability {
        case .available: Color.green.opacity(0.2)
        case .flexed: Color.orange.opacity(0.2)
        case .conflict: Color(.systemGray5).opacity(0.5)
        }
    }

    private var borderColor: Color {
        if isSelected { return DougTheme.sourdoughBrown }
        switch slot.viability {
        case .available: return .green.opacity(0.6)
        case .flexed: return .orange.opacity(0.6)
        case .conflict: return .clear
        }
    }

    private var textOpacity: Double {
        switch slot.viability {
        case .conflict: 0.35
        default: 1.0
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                switch slot.viability {
                case .available:
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                case .flexed:
                    Image(systemName: "minus")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                case .conflict:
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }

                Text(slot.time, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .monospacedDigit()
                    .opacity(textOpacity)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(backgroundColor, in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDescription)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                onInfo()
            }
        )
    }

    private var accessibilityDescription: String {
        let timeStr = slot.time.formatted(date: .omitted, time: .shortened)
        switch slot.viability {
        case .available:
            return "\(timeStr), available"
        case let .flexed(details):
            let step = details.first?.stepLabel ?? "a step"
            return "\(timeStr), tight schedule — \(step) shortened"
        case let .conflict(c):
            return "\(timeStr), conflict — \(c.conflictingStepLabel) overlaps with \(c.conflictingWindowName)"
        }
    }
}
