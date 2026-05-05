import ActivityKit
import SwiftUI
import WidgetKit

struct RevivalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RevivalActivityAttributes.self) { context in
            RevivalLockScreenView(state: context.state)
                .activityBackgroundTint(LiveActivityColors.sourdoughBrown.opacity(0.9))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image("DougIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text(context.state.feedLabel)
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.feedStatus == "inProgress" {
                        if let peakTime = context.state.expectedPeakTime {
                            Text(peakTime, style: .timer)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(LiveActivityColors.crustGold)
                        } else if let start = context.state.risingStartTime {
                            Text(start, style: .timer)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(LiveActivityColors.crustGold)
                        }
                    } else if let mixTime = context.state.scheduledMixTime {
                        Text(mixTime, style: .timer)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(LiveActivityColors.crustGold)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.feedStatus == "inProgress",
                           let minPeak = context.state.minPeakTime,
                           let maxPeak = context.state.maxPeakTime
                        {
                            Text("Peak: \(minPeak, format: .dateTime.hour().minute())–\(maxPeak, format: .dateTime.hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let bakeReady = context.state.estimatedBakeReadyDate {
                            Text("Bake-ready ~\(bakeReady, format: .dateTime.month().day().hour().minute())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Label {
                    Text(context.state.feedLabel)
                        .font(.caption2)
                        .lineLimit(1)
                } icon: {
                    Image("DougIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            } compactTrailing: {
                if context.state.feedStatus == "inProgress" {
                    if let peakTime = context.state.expectedPeakTime {
                        Text(peakTime, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(LiveActivityColors.crustGold)
                    } else if let start = context.state.risingStartTime {
                        Text(start, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(LiveActivityColors.crustGold)
                    }
                } else if let mixTime = context.state.scheduledMixTime {
                    Text(mixTime, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(LiveActivityColors.crustGold)
                }
            } minimal: {
                Image("DougIcon")
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

private struct RevivalLockScreenView: View {
    let state: RevivalActivityAttributes.ContentState

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
                        Image(systemName: "bubbles.and.sparkles")
                            .foregroundStyle(LiveActivityColors.crustGold)
                        if state.feedStatus == "inProgress" {
                            Text("\(state.feedLabel) — Rising")
                        } else {
                            Text(state.feedLabel)
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(LiveActivityColors.warmCream)

                    if state.feedStatus == "inProgress", let start = state.risingStartTime {
                        HStack(spacing: 4) {
                            Text("Started")
                            Text(start, style: .relative)
                        }
                        .font(.caption)
                        .foregroundStyle(LiveActivityColors.warmParchment.opacity(0.7))
                    } else if let mixTime = state.scheduledMixTime {
                        HStack(spacing: 4) {
                            Text("Mix at \(mixTime, format: .dateTime.hour().minute())")
                            Text("(\(mixTime, style: .relative))")
                        }
                        .font(.caption)
                        .foregroundStyle(LiveActivityColors.warmParchment.opacity(0.7))
                    }
                }
                Spacer()
                Text("\(state.currentStepIndex + 1)/\(state.totalSteps)")
                    .font(.caption2)
                    .foregroundStyle(LiveActivityColors.warmParchment.opacity(0.7))
            }

            HStack {
                if state.feedStatus == "inProgress",
                   let minPeak = state.minPeakTime,
                   let maxPeak = state.maxPeakTime
                {
                    Text("Peak window: \(minPeak, format: .dateTime.hour().minute())–\(maxPeak, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundStyle(LiveActivityColors.warmParchment.opacity(0.7))
                }
                Spacer()
                if let bakeReady = state.estimatedBakeReadyDate {
                    Text("Bake-ready ~\(bakeReady, format: .dateTime.month().day().hour().minute())")
                        .font(.caption)
                        .foregroundStyle(LiveActivityColors.crustGold)
                }
            }
        }
        .padding()
    }
}
