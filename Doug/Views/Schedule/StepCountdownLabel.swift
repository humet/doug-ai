import SwiftUI

/// Live countdown / status label for a `ScheduleStep`, computed relative to a
/// reference date so a parent `TimelineView` can drive all rows from a single ticker.
struct StepCountdownLabel: View {
    let step: ScheduleStep
    let referenceDate: Date

    var body: some View {
        Text(phrase)
            .font(.caption.monospacedDigit())
            .foregroundStyle(color)
    }

    private var phrase: String {
        switch step.stepStatus {
        case .upcoming:
            let remaining = step.computedStartTime.timeIntervalSince(referenceDate)
            if remaining > 0 {
                return "starts in \(Self.format(seconds: remaining))"
            }
            return "starting now"
        case .active:
            let remaining = step.computedEndTime.timeIntervalSince(referenceDate)
            if remaining > 0 {
                return "\(Self.format(seconds: remaining)) remaining"
            }
            let overdue = -remaining
            return "\(Self.format(seconds: overdue)) overdue"
        case .done:
            let actualEnd = step.actualEndTime ?? step.computedEndTime
            let elapsed = referenceDate.timeIntervalSince(actualEnd)
            if elapsed < 60 * 60 {
                return "finished \(Self.format(seconds: max(0, elapsed))) ago"
            }
            return "finished at \(Self.timeFormatter.string(from: actualEnd))"
        case .skipped:
            return "skipped"
        }
    }

    private var color: Color {
        switch step.stepStatus {
        case .upcoming:
            return .secondary
        case .active:
            let remaining = step.computedEndTime.timeIntervalSince(referenceDate)
            if remaining < 0 { return .red }
            if remaining < 5 * 60 { return .red }
            return DougTheme.stepActive
        case .done:
            return DougTheme.stepDone
        case .skipped:
            return DougTheme.stepSkipped
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func format(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        }
        return String(format: "%ds", max(0, secs))
    }
}
