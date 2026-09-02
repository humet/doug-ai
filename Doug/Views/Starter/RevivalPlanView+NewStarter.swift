import SwiftUI

/// The parts of the plan view that only apply to building a new starter.
///
/// A revival step is peak-driven: feed, wait, mark the peak. The early steps of
/// a new starter are not — on day two there is nothing to peak, so the step
/// needs a plain "I fed it" and a question about what the user can see. That
/// observation, not the clock, is what moves the plan along.
extension RevivalPlanView {
    // MARK: - Header

    var newStarterHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dayLabel)
                    .font(.headline)
                Spacer()
                statusBadge
            }

            if plan.revivalStatus == .active {
                HStack(spacing: 8) {
                    Image(systemName: phaseIcon)
                        .foregroundStyle(Color.accentColor)
                    Text(phaseLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let ready = plan.estimatedBakeReadyDate, plan.revivalStatus == .active {
                HStack {
                    Label("Ready around", systemImage: "calendar")
                    Spacer()
                    RelativeTimeLabel(date: ready)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    var dayLabel: String {
        let day = currentStep?.dayNumber ?? 1
        guard let total = estimatedTotalDays, total > day else {
            return "Day \(day)"
        }
        // "About" matters — the plan stretches and shrinks as it goes.
        return "Day \(day) of about \(total)"
    }

    /// Estimated total days from the last step in the plan as it stands now.
    var estimatedTotalDays: Int? {
        sortedSteps.last?.dayNumber
    }

    var phaseLabel: String {
        switch plan.establishPhase {
        case .initialMix: "Getting started"
        case .dailyFeeds: "Feeding once a day"
        case .twiceDailyFeeds: "Feeding twice a day — building strength"
        case .confirming: "Confirming it's ready to bake with"
        case nil: ""
        }
    }

    var phaseIcon: String {
        switch plan.establishPhase {
        case .initialMix: "drop"
        case .dailyFeeds: "sun.max"
        case .twiceDailyFeeds: "chart.line.uptrend.xyaxis"
        case .confirming: "checkmark.seal"
        case nil: "circle"
        }
    }

    // MARK: - Actions

    /// The action for a step where nothing is expected to rise. There is no
    /// peak to wait for, so feeding is the whole step.
    func establishFeedButton(_ step: RevivalFeedStep) -> some View {
        Button {
            cancelMixReminder(for: step)
            // The opening mix has nothing to observe yet — the jar is empty.
            if step.sequenceIndex == 0 {
                handleCheckIn(nil, step: step)
            } else {
                checkInStep = step
            }
        } label: {
            Text(step.sequenceIndex == 0 ? "I've mixed it" : "I've fed it")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("establishFeedButton")
    }

    /// Shown once a peak-expecting establishment step has peaked.
    func establishCheckInPrompt(_ step: RevivalFeedStep) -> some View {
        Button {
            checkInStep = step
        } label: {
            Label("Log what you saw", systemImage: "eye")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("establishCheckInPrompt")
    }

    func handleCheckIn(_ signals: StarterCheckInSignals?, step: RevivalFeedStep) {
        viewModel.recordEstablishCheckIn(
            step: step,
            plan: plan,
            signals: signals,
            availability: availabilities.first,
            windows: Array(windows),
            profile: profiles.first
        )
    }

    // MARK: - Outcome

    /// Explains what the last check-in changed. The false-rise card is the one
    /// that earns its keep: an early bloom that then collapses is the most
    /// common reason people bin a starter that was doing fine.
    @ViewBuilder
    var outcomeCard: some View {
        switch plan.establishNotice {
        case .falseRise:
            noticeCard(
                icon: "exclamationmark.bubble.fill",
                tint: .orange,
                title: "That's not failure",
                body: StarterEstablishProgress.falseRiseExplanation
            )
        case .stalled:
            noticeCard(
                icon: "thermometer.low",
                tint: .orange,
                title: "Let's give it more help",
                body: plan.starterOrigin.map(StarterEstablishProgress.stallAdvice(for:)) ?? ""
            )
        case .advanced:
            noticeCard(
                icon: "hare.fill",
                tint: .green,
                title: "Ahead of schedule",
                body: plan.establishPhase.map(advanceMessage(for:)) ?? ""
            )
        case .needsMoreConfirming:
            noticeCard(
                icon: "arrow.clockwise",
                tint: .orange,
                title: "Not quite there",
                body: "It needs to double inside the window to count, so more confirming feeds "
                    + "have been added — most starters get there within a day or two."
            )
        case .complete:
            noticeCard(
                icon: "party.popper.fill",
                tint: .green,
                title: "You have a starter",
                body: "It doubled reliably, which means it's strong enough to raise a loaf. "
                    + "It's on the counter and ready — build a levain, or feed it and put it in the fridge."
            )
        case nil:
            EmptyView()
        }
    }

    private func advanceMessage(for phase: StarterEstablishPhase) -> String {
        switch phase {
        case .dailyFeeds:
            "Mixed and resting. From here it's one feed a day while the yeast establishes."
        case .twiceDailyFeeds:
            "The yeast has taken hold sooner than usual, so we've skipped ahead to twice-daily "
                + "feeds. Earlier steps have been dropped from the plan."
        case .confirming:
            "It's doubling. Now it just has to prove it can do that reliably — "
                + "the remaining feeds are the test."
        case .initialMix:
            "Starting over from the first mix."
        }
    }

    private func noticeCard(
        icon: String,
        tint: Color,
        title: String,
        body: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.bold())
                Text(body)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("starterPlanNotice")
    }
}
