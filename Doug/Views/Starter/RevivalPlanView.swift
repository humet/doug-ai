import SwiftData
import SwiftUI

/// Step-by-step revival guide.
///
/// Focuses on the current step (`plan.currentStepIndex`) so the user only sees what
/// they need to do right now. When a step is marked in-progress late or peaks
/// outside its tolerance band, later scheduled times cascade-shift and the preview
/// list below telegraphs the change.
struct RevivalPlanView: View {
    @Bindable var plan: RevivalPlan

    @Environment(\.modelContext) private var modelContext
    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = StarterViewModel()
    @State private var isReminderPending = false

    var body: some View {
        List {
            if plan.currentStepIndex == 0, let opening = plan.coachOpeningRead, !opening.isEmpty {
                Section {
                    Text(opening)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }

            headerSection

            if let step = currentStep {
                currentStepSection(step)
            }

            upcomingStepsSection

            if plan.revivalStatus == .active {
                Section {
                    Button("Cancel Revival", role: .destructive) {
                        NotificationService.shared.cancelAllRevivalReminders(
                            planID: notificationPlanID,
                            stepCount: sortedSteps.count
                        )
                        plan.revivalStatus = .cancelled
                    }
                }
            }
        }
        .navigationTitle("Revival")
        .task(id: plan.currentStepIndex) {
            await refreshReminderState()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack {
                Text("Step \(plan.currentStepIndex + 1) of \(sortedSteps.count)")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            if let bakeReady = plan.estimatedBakeReadyDate, plan.revivalStatus == .active {
                HStack {
                    Label("Bake-ready", systemImage: "calendar")
                    Spacer()
                    RelativeTimeLabel(date: bakeReady)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func currentStepSection(_ step: RevivalFeedStep) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let title = step.instructionTitle, !title.isEmpty {
                    Text(title)
                        .font(.title3.bold())
                }

                switch step.feedStatus {
                case .pending:
                    pendingContent(step)
                case .inProgress:
                    inProgressContent(step)
                case .completed:
                    Label("Completed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func pendingContent(_ step: RevivalFeedStep) -> some View {
        scheduledTimeRow(step)

        gramsPanel(step)

        if let bulletsText = step.instructionBody, !bulletsText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bulletLines(bulletsText).enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(idx + 1).")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(line)
                            .font(.subheadline)
                    }
                }
            }
        }

        if let watch = step.instructionWatchFor, !watch.isEmpty {
            Label {
                Text(watch)
                    .font(.footnote)
            } icon: {
                Image(systemName: "eye")
            }
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 6) {
            Image(systemName: "clock")
            Text("Expected wait: \(step.instructionExpectedWait ?? "")")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)

        whatToDoCard

        latenessCallout(step)

        actionButton(for: step)
    }

    private var whatToDoCard: some View {
        Label {
            Text("Mix the feed above, then tap the button below to start. You'll watch for peak and mark it when your starter stops rising.")
                .font(.footnote)
        } icon: {
            Image(systemName: "hand.point.up")
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    @ViewBuilder
    private func inProgressContent(_ step: RevivalFeedStep) -> some View {
        if let startedAt = step.startedAt {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text("Rising for ")
                Text(startedAt, style: .timer)
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        peakWindowCard(step)

        let guidance = step.instructionPeakGuidance ?? step.instructionWatchFor
        if let guidance, !guidance.isEmpty {
            Label {
                Text(guidance)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "eye.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.10))
            )
        }

        latenessCallout(step)

        timeFallbackCard(step)

        Button {
            viewModel.markRevivalStepPeak(
                step: step,
                plan: plan,
                availability: availabilities.first,
                windows: Array(windows)
            )
        } label: {
            Label("Mark peak now", systemImage: "arrow.up.to.line")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private func peakWindowCard(_ step: RevivalFeedStep) -> some View {
        if let startedAt = step.startedAt {
            let minTime = startedAt.addingTimeInterval((step.minPeakMinutes ?? step.expectedPeakMinutes * 0.75) * 60)
            let maxTime = startedAt.addingTimeInterval((step.maxPeakMinutes ?? step.expectedPeakMinutes * 1.5) * 60)

            VStack(alignment: .leading, spacing: 6) {
                Text("Expected peak window")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(minTime, format: .dateTime.hour().minute()) – \(maxTime, format: .dateTime.hour().minute())")
                        .font(.subheadline.bold())
                    Spacer()
                    peakWindowBadge(startedAt: startedAt, step: step)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private func peakWindowBadge(startedAt: Date, step: RevivalFeedStep) -> some View {
        let elapsed = Date().timeIntervalSince(startedAt) / 60
        let min = step.minPeakMinutes ?? step.expectedPeakMinutes * 0.75
        let max = step.maxPeakMinutes ?? step.expectedPeakMinutes * 1.5

        let (text, color): (String, Color) = if elapsed < min {
            ("Too early", .secondary)
        } else if elapsed <= max {
            ("In the window", .green)
        } else {
            ("Past expected", .orange)
        }

        return Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func timeFallbackCard(_ step: RevivalFeedStep) -> some View {
        if let startedAt = step.startedAt {
            let elapsed = Date().timeIntervalSince(startedAt) / 60
            let max = step.maxPeakMinutes ?? step.expectedPeakMinutes * 1.5
            let isSevere = plan.assessedNeglect == StarterNeglectLevel.severe.rawValue
            let threshold = isSevere ? step.expectedPeakMinutes * 1.1 : max

            if elapsed > threshold {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(isSevere
                            ? "Your starter may not show a clear peak yet — that's normal after long neglect. You can move to the next feed."
                            : "It's been longer than expected. If activity has slowed, you can move on.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                    }
                    .foregroundStyle(.orange)

                    Button {
                        viewModel.markRevivalStepPeak(
                            step: step,
                            plan: plan,
                            availability: availabilities.first,
                            windows: Array(windows)
                        )
                    } label: {
                        Text("Move to next feed")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.10))
                )
            }
        }
    }

    @ViewBuilder
    private func scheduledTimeRow(_ step: RevivalFeedStep) -> some View {
        if step.feedStatus == .pending {
            let now = Date()
            let isFuture = step.scheduledTime > now
            let isRecent = !isFuture && now.timeIntervalSince(step.scheduledTime) < 5 * 60

            if isRecent {
                // Just created or very recent — no stale time display needed
            } else {
                HStack(spacing: 8) {
                    Image(systemName: isFuture ? "calendar.badge.clock" : "calendar")
                    VStack(alignment: .leading, spacing: 2) {
                        if isFuture {
                            Text("Mix at \(step.scheduledTime, format: .dateTime.weekday(.wide).hour().minute())")
                                .font(.subheadline.bold())
                            RelativeTimeLabel(date: step.scheduledTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Scheduled for \(step.scheduledTime, format: .dateTime.weekday(.abbreviated).hour().minute())")
                                .font(.footnote)
                            Text("Passed — mix when ready")
                                .font(.caption2)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isFuture ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemBackground))
                )
                .foregroundStyle(isFuture ? Color.accentColor : .secondary)
            }
        }
    }

    @ViewBuilder
    private func latenessCallout(_ step: RevivalFeedStep) -> some View {
        let now = Date()
        if step.feedStatus == .pending,
           now.timeIntervalSince(step.scheduledTime) > 30 * 60
        {
            Label {
                Text("You're running a little late — when you mix, the next feed will shift to fit.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .foregroundStyle(.orange)
        } else if step.feedStatus == .inProgress,
                  let startedAt = step.startedAt,
                  let max = step.maxPeakMinutes,
                  now.timeIntervalSince(startedAt) > max * 60
        {
            Label {
                Text("Peak is slower than expected — that's okay. Marking peak now will push the next feed back.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "hourglass")
            }
            .foregroundStyle(.orange)
        }

        overnightPeakCallout(step)
    }

    @ViewBuilder
    private func overnightPeakCallout(_ step: RevivalFeedStep) -> some View {
        if step.feedStatus != .completed, peakFallsOvernight(step) {
            let peakTime = expectedPeakTime(step)
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peak likely around \(peakTime, format: .dateTime.hour().minute()) — while you'd usually be asleep.")
                        .font(.footnote)
                    Text("Mark peak when you wake up. The rest of the plan will shift to fit your day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "moon.zzz")
            }
            .foregroundStyle(.orange)
        }
    }

    private func expectedPeakTime(_ step: RevivalFeedStep) -> Date {
        let reference = step.startedAt ?? step.scheduledTime
        return reference.addingTimeInterval(step.expectedPeakMinutes * 60)
    }

    private func peakFallsOvernight(_ step: RevivalFeedStep) -> Bool {
        let availInput = availabilities.first.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
        let windowInputs = windows.map { WindowInput(from: $0) }
        return RevivalTiming.peakFallsInUnavailable(
            startTime: step.startedAt ?? step.scheduledTime,
            expectedPeakMinutes: step.expectedPeakMinutes,
            availability: availInput,
            windows: windowInputs
        )
    }

    private func gramsPanel(_ step: RevivalFeedStep) -> some View {
        HStack(spacing: 14) {
            if let retain = step.retainStarterGrams {
                gramsColumn(label: "Retain", grams: retain)
            }
            if let flour = step.addFlourGrams {
                gramsColumn(label: "+ Flour", grams: flour)
            }
            if let water = step.addWaterGrams {
                gramsColumn(label: "+ Water", grams: water)
            }
            if let total = totalGrams(step) {
                Divider()
                    .frame(height: 36)
                gramsColumn(label: "Total", grams: total, emphasise: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func gramsColumn(label: String, grams: Double, emphasise: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(grams.rounded())) g")
                .font(emphasise ? .headline : .subheadline)
                .fontWeight(emphasise ? .bold : .medium)
        }
        .frame(maxWidth: .infinity)
    }

    private func totalGrams(_ step: RevivalFeedStep) -> Double? {
        guard let retain = step.retainStarterGrams,
              let flour = step.addFlourGrams,
              let water = step.addWaterGrams
        else { return nil }
        return retain + flour + water
    }

    private func reminderSetCard(for step: RevivalFeedStep) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reminder set")
                    .font(.subheadline.bold())
                Text("We'll ping you at \(step.scheduledTime, format: .dateTime.hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionButton(for step: RevivalFeedStep) -> some View {
        if step.scheduledTime > Date() {
            VStack(spacing: 10) {
                if isReminderPending {
                    reminderSetCard(for: step)

                    Button(role: .destructive) {
                        cancelMixReminder(for: step)
                    } label: {
                        Text("Cancel reminder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button {
                        Task { await scheduleMixReminder(for: step) }
                    } label: {
                        Text("Remind me at \(step.scheduledTime, format: .dateTime.hour().minute())")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button {
                    if isReminderPending {
                        cancelMixReminder(for: step)
                    }
                    viewModel.markRevivalStepStarted(
                        step: step,
                        plan: plan,
                        availability: availabilities.first,
                        windows: Array(windows)
                    )
                } label: {
                    Text("I've already mixed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .sensoryFeedback(.success, trigger: isReminderPending)
        } else {
            Button {
                viewModel.markRevivalStepStarted(
                    step: step,
                    plan: plan,
                    availability: availabilities.first,
                    windows: Array(windows)
                )
            } label: {
                Text("I've mixed & covered")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var upcomingStepsSection: some View {
        let pending = sortedSteps.filter { $0.sequenceIndex > plan.currentStepIndex }
        if !pending.isEmpty, plan.revivalStatus == .active {
            Section {
                ForEach(pending) { step in
                    upcomingRow(step)
                }
            } header: {
                Text("Upcoming")
            }
        }
    }

    private func upcomingRow(_ step: RevivalFeedStep) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Feed \(step.sequenceIndex + 1)")
                    .font(.subheadline.bold())
                Spacer()
                Text(step.scheduledTime, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let original = step.originalScheduledTime,
               abs(original.timeIntervalSince(step.scheduledTime)) > 60
            {
                Text("Shifted from \(original, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let retain = step.retainStarterGrams,
               let flour = step.addFlourGrams,
               let water = step.addWaterGrams
            {
                Text(
                    "Retain \(Int(retain.rounded())) g · +\(Int(flour.rounded())) g flour · +\(Int(water.rounded())) g water"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var sortedSteps: [RevivalFeedStep] {
        plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    private var currentStep: RevivalFeedStep? {
        sortedSteps.first(where: { $0.sequenceIndex == plan.currentStepIndex })
            ?? sortedSteps.last
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch plan.revivalStatus {
        case .active:
            Text("Active")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.orange, in: .capsule)
        case .completed:
            Text("Complete")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.green, in: .capsule)
        case .cancelled:
            Text("Cancelled")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.secondary, in: .capsule)
        }
    }

    private var notificationPlanID: String {
        plan.persistentModelID.hashValue.description
    }

    private func scheduleMixReminder(for step: RevivalFeedStep) async {
        await NotificationService.shared.scheduleRevivalMixReminder(
            at: step.scheduledTime,
            planID: notificationPlanID,
            stepIndex: step.sequenceIndex,
            title: step.instructionTitle ?? "Feed \(step.sequenceIndex + 1)"
        )
        isReminderPending = true
    }

    private func cancelMixReminder(for step: RevivalFeedStep) {
        NotificationService.shared.cancelRevivalMixReminder(
            planID: notificationPlanID,
            stepIndex: step.sequenceIndex
        )
        isReminderPending = false
    }

    private func refreshReminderState() async {
        guard let step = currentStep, step.scheduledTime > Date() else {
            isReminderPending = false
            return
        }
        isReminderPending = await NotificationService.shared.hasPendingRevivalMixReminder(
            planID: notificationPlanID,
            stepIndex: step.sequenceIndex
        )
    }

    private func bulletLines(_ body: String) -> [String] {
        body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
