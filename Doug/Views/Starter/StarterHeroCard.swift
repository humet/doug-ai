import SwiftUI

/// Actions the hero card can emit; the Starter tab owns what they do.
enum StarterHeroAction {
    case activateAndFeed
    case logActivationFeed
    case markPeak
    case buildLevain
    case feedAndRefrigerate
    case logMaintenanceFeed
    case refrigerate
    case startNewStarter
}

/// State-first summary of the starter: what it's doing right now and the one
/// action to take next. Replaces the old status rows + button pile.
struct StarterHeroCard: View {
    let state: StarterLifecycleState
    let healthStatus: StarterHealthStatus
    let storageType: StarterStorageType
    let lastFeedDate: Date?
    let risingSince: Date?
    let expectedPeak: Date?
    let stateChangedAt: Date?
    let bakeAwaitingLevainMix: Bool
    let primaryAction: StarterPrimaryAction
    let now: Date
    let onAction: (StarterHeroAction) -> Void

    var body: some View {
        statusRow
        detailRow
        risingLine
        actionButtons
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 4)
    }

    private var detailRow: some View {
        HStack(spacing: 16) {
            // Storage is meaningless until there's something to store.
            if !(state == .dormant && healthStatus == .establishing) {
                Label(
                    storageType == .counter ? "Counter" : "Fridge",
                    systemImage: storageType == .counter ? "sun.max" : "refrigerator"
                )
            }
            Label(healthText, systemImage: healthIcon)
                .foregroundStyle(healthColor)
            if let lastFeedDate {
                Label {
                    RelativeTimeLabel(date: lastFeedDate)
                } icon: {
                    Image(systemName: "clock")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// "Rising since 7:12 — expect peak ~13:40" while a feed is mid-rise.
    @ViewBuilder
    private var risingLine: some View {
        if let risingSince, let expectedPeak {
            let sinceText = risingSince.formatted(.dateTime.hour().minute())
            let peakText = expectedPeak.formatted(.dateTime.hour().minute())
            let overdue = expectedPeak <= now
            Label(
                overdue
                    ? "Rising since \(sinceText) — should have peaked by now, check it"
                    : "Rising since \(sinceText) — expect peak ~\(peakText)",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            .font(.caption)
            .foregroundStyle(overdue ? Color.orange : Color.green)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionButtons: some View {
        switch primaryAction {
        case .activateAndFeed:
            prominentButton("Activate & Feed", tint: .orange) { onAction(.activateAndFeed) }
            Button {
                onAction(.logMaintenanceFeed)
            } label: {
                Label("Log Maintenance Feed", systemImage: "snowflake")
            }
        case .logActivationFeed:
            prominentButton("Log Activation Feed", tint: .orange) { onAction(.logActivationFeed) }
            refrigerateButton
        case .markPeak:
            prominentButton("Mark Peak", tint: .green) { onAction(.markPeak) }
            refrigerateButton
        case .buildLevain:
            prominentButton("Log Levain Build", tint: .green) { onAction(.buildLevain) }
            Button {
                onAction(.feedAndRefrigerate)
            } label: {
                Label("Feed & Refrigerate", systemImage: "snowflake")
            }
        case .feedAndRefrigerate:
            prominentButton("Feed & Refrigerate", tint: .accentColor) { onAction(.feedAndRefrigerate) }
        case .waitForBake:
            HStack(spacing: 8) {
                Image(systemName: "oven")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bake in progress")
                        .font(.subheadline.weight(.medium))
                    Text("Feed after the levain is mixed in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .followRevival, .followStarterPlan:
            EmptyView() // the plan section below carries the call to action
        case .startNewStarter:
            prominentButton("Start a Starter", tint: .accentColor) { onAction(.startNewStarter) }
        }
    }

    private func prominentButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private var refrigerateButton: some View {
        Button {
            onAction(.refrigerate)
        } label: {
            Label("Put Back in Fridge", systemImage: "snowflake")
        }
    }

    // MARK: - Display derivations

    private var icon: String {
        switch state {
        case .dormant: healthIcon
        case .activating: "flame.fill"
        case .active: "checkmark.circle.fill"
        case .reviving: "arrow.triangle.2.circlepath.circle.fill"
        case .establishing: "sparkles"
        }
    }

    private var color: Color {
        switch state {
        case .dormant: healthColor
        case .activating: .orange
        case .active: DougTheme.starterReady
        case .reviving: .accentColor
        case .establishing: .accentColor
        }
    }

    private var title: String {
        switch state {
        case .dormant: healthStatus == .establishing ? "No Starter Yet" : "In the Fridge"
        case .activating: risingSince != nil ? "Waking Up" : "Activating"
        case .active: bakeAwaitingLevainMix ? "Powering Your Bake" : "Ready to Bake!"
        case .reviving: "In Revival"
        case .establishing: "Building a Starter"
        }
    }

    private var subtitle: String {
        switch state {
        case .dormant:
            if let lastFeedDate {
                let days = Int(now.timeIntervalSince(lastFeedDate) / 86400)
                return "Last fed \(days) day\(days == 1 ? "" : "s") ago"
            }
            if healthStatus == .establishing {
                return "You don't have a starter yet — let's make one"
            }
            return "No feeds logged yet"
        case .activating:
            if let risingSince {
                let hours = Int(now.timeIntervalSince(risingSince) / 3600)
                return "Rising on the counter — \(hours)h since feed"
            }
            return "Feed your starter on the counter to wake it up"
        case .active:
            let hours = Int(now.timeIntervalSince(stateChangedAt ?? now) / 3600)
            if bakeAwaitingLevainMix {
                return "Active for \(hours)h — feed & refrigerate once it's mixed into your dough"
            }
            return "Active for \(hours)h — build your levain or feed & refrigerate"
        case .reviving:
            return "Your starter is rebuilding strength. Follow the revival plan below."
        case .establishing:
            return "A new starter is on the way. Follow the plan below."
        }
    }

    private var healthText: String {
        switch healthStatus {
        case .readyToBake: "Healthy"
        case .needsFeed: "Needs feed"
        case .needsRevival: "Needs revival"
        case .establishing: "Getting started"
        }
    }

    private var healthIcon: String {
        switch healthStatus {
        case .readyToBake: "checkmark.circle.fill"
        case .needsFeed: "exclamationmark.circle.fill"
        case .needsRevival: "xmark.circle.fill"
        case .establishing: "sparkles"
        }
    }

    private var healthColor: Color {
        switch healthStatus {
        case .readyToBake: DougTheme.starterReady
        case .needsFeed: DougTheme.starterNeedsFeed
        case .needsRevival: DougTheme.starterNeedsRevival
        case .establishing: .accentColor
        }
    }
}

// MARK: - Typical Rise Row

/// Surfaces the personalised time-to-peak the scheduler plans with, so the user
/// can sanity-check it (and spot bad feed data) at a glance. Same input the
/// builder uses: activation feeds at the standard 1:5:5 levain ratio.
struct TypicalRiseRow: View {
    let feedLogs: [StarterFeedLog]

    var body: some View {
        let peakProfile = StarterPeakProfile(
            feedLogs: feedLogs.map { FeedLogInput(from: $0) },
            intentFilter: .activation
        )
        let latestActivationTemp = feedLogs
            .first(where: { $0.starterFeedIntent == .activation })?
            .kitchenTemperatureCelsius

        switch peakProfile.typicalRise(ratio: .oneToFive, nearTemperatureCelsius: latestActivationTemp) {
        case let .known(minutes, bracket, matchesCurrentTemp):
            let hours = Int((minutes / 60).rounded())
            if minutes > StarterPeakProfile.unusuallyLongRiseMinutes {
                Label(
                    "Typically ~\(hours)h to peak — unusually long, check your feed history",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                let context: String = if matchesCurrentTemp, let temp = latestActivationTemp {
                    "at \(Int(temp.rounded()))°C"
                } else {
                    Self.bracketPhrase(bracket)
                }
                Label("Typically ~\(hours)h to peak \(context)", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .insufficientData:
            if feedLogs.contains(where: { $0.starterFeedIntent == .activation }) {
                Label(
                    "Log a couple more activations to learn your starter's rhythm",
                    systemImage: "hourglass"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private static func bracketPhrase(_ bracket: TemperatureBracket) -> String {
        switch bracket {
        case .cool: "in a cool kitchen"
        case .moderate: "at room temp"
        case .warm: "in a warm kitchen"
        }
    }
}
