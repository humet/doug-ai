import ActivityKit
import SwiftUI
import WidgetKit

struct BakeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BakeActivityAttributes.self) { context in
            BakeLockScreenView(state: context.state)
                .activityBackgroundTint(LiveActivityColors.sourdoughBrown.opacity(0.9))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image("DougIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text(context.state.currentStepLabel)
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Text("Paused")
                            .font(.caption.bold())
                            .foregroundStyle(.yellow)
                    } else {
                        Text(context.state.stepEndTime, style: .timer)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(context.state.isOverdue ? .red : LiveActivityColors.crustGold)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let nextLabel = context.state.nextStepLabel,
                           let nextTime = context.state.nextStepStartTime
                        {
                            Text("Next: \(nextLabel) at \(nextTime, format: .dateTime.hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(context.state.completedStepCount)/\(context.state.totalStepCount) steps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                if context.state.isPaused {
                    Label {
                        Text("Paused")
                            .font(.caption2)
                    } icon: {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.yellow)
                    }
                } else {
                    Label {
                        Text(context.state.currentStepLabel)
                            .font(.caption2)
                            .lineLimit(1)
                    } icon: {
                        Image("DougIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
            } compactTrailing: {
                if context.state.isPaused {
                    Text("Paused")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                } else {
                    Text(context.state.stepEndTime, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(context.state.isOverdue ? .red : LiveActivityColors.crustGold)
                }
            } minimal: {
                Image("DougIcon")
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

private struct BakeLockScreenView: View {
    let state: BakeActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image("DougIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(LiveActivityColors.warmCream)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if state.isPaused {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(.yellow)
                            Text("Bake Paused")
                        } else {
                            Image(systemName: state.currentStepIcon)
                                .foregroundStyle(LiveActivityColors.crustGold)
                            Text(state.currentStepLabel)
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(LiveActivityColors.warmCream)
                    if state.isPaused {
                        Text("Open Doug to resume")
                            .font(.caption)
                            .foregroundStyle(LiveActivityColors.warmParchment.opacity(0.7))
                    } else if state.isOverdue {
                        Text("Overdue")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    } else {
                        Text(state.stepEndTime, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(LiveActivityColors.warmParchment.opacity(0.7))
                    }
                }
                Spacer()
                Text("\(state.completedStepCount) of \(state.totalStepCount)")
                    .font(.caption2)
                    .foregroundStyle(LiveActivityColors.warmParchment.opacity(0.7))
            }

            if !state.isPaused {
                HStack {
                    if let nextLabel = state.nextStepLabel,
                       let nextTime = state.nextStepStartTime
                    {
                        Text("Next: \(nextLabel) at \(nextTime, format: .dateTime.hour().minute())")
                            .font(.caption)
                            .foregroundStyle(LiveActivityColors.warmParchment.opacity(0.7))
                    }
                    Spacer()
                    Text("Ready ~\(state.breadReadyTime, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundStyle(LiveActivityColors.crustGold)
                }
            }
        }
        .padding()
    }
}
