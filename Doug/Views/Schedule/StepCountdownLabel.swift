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
            return "up next"
        case .active:
            let anchor = step.schedule?.pausedAt ?? referenceDate
            let remaining = step.computedEndTime.timeIntervalSince(anchor)
            if remaining > 0 {
                return "\(Self.format(seconds: remaining)) remaining"
            }
            let overdue = -remaining
            if step.stepType.classification == .passiveFlexible {
                return "\(Self.format(seconds: overdue)) over — resting"
            }
            let stepID = StepTypeID(rawValue: step.stepTypeID)
            if stepID == .buildLevain || stepID == .waitForPeak {
                return "waiting for peak"
            }
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
            let anchor = step.schedule?.pausedAt ?? referenceDate
            let remaining = step.computedEndTime.timeIntervalSince(anchor)
            if remaining < 0 {
                let stepID = StepTypeID(rawValue: step.stepTypeID)
                if step.stepType.classification == .passiveFlexible
                    || stepID == .buildLevain || stepID == .waitForPeak
                {
                    return DougTheme.stepActive
                }
                return .red
            }
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
        LiveActivityFormatting.formatCountdown(seconds: seconds)
    }
}
