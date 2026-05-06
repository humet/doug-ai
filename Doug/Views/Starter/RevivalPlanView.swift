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
    @State private var bakeReady: Bool?

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

            completedStepsSection

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
        .task(id: currentStep?.status) {
            await refreshReminderState()
            bakeReady = nil
        }


    }

    // MARK: - Sections

    @ViewBuilder
    private var completedStepsSection: some View {
        let completed = sortedSteps.filter { $0.feedStatus == .completed }
        if !completed.isEmpty {
            Section {
                ForEach(completed) { step in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(step.instructionTitle ?? "Feed \(step.sequenceIndex + 1)")
                            .font(.subheadline)
                        Spacer()
                        Text(peakDurationLabel(step))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

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
                case .peaked:
                    peakedContent(step)
                case .completed:
                    completedContent(step)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func pendingContent(_ step: RevivalFeedStep) -> some View {
        let isWaiting = step.scheduledTime > Date()

        scheduledTimeRow(step)

        if isWaiting {
            waitingContent(step)
        } else {
            readyToMixContent(step)
        }
    }

    @ViewBuilder
    private func waitingContent(_ step: RevivalFeedStep) -> some View {
        gramsPanel(step)

        HStack(spacing: 6) {
            Image(systemName: "clock")
            Text("Expected wait after feeding: \(step.instructionExpectedWait ?? "")")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)

        actionButton(for: step)

        if let bulletsText = step.instructionBody, !bulletsText.isEmpty {
            DisclosureGroup("View instructions") {
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
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func readyToMixContent(_ step: RevivalFeedStep) -> some View {
        latenessCallout(step)

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

        HStack(spacing: 6) {
            Image(systemName: "clock")
            Text("Expected wait: \(step.instructionExpectedWait ?? "")")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)

        actionButton(for: step)
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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye.fill")
                    .foregroundStyle(Color.accentColor)
                Text(guidance)
                    .font(.subheadline)
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
    private func completedContent(_ step: RevivalFeedStep) -> some View {
        if plan.revivalStatus == .completed {
            VStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text("Your starter is back")
                    .font(.headline)

                Text("Doubled in \(formattedDuration(step.timeToPeakMinutes)) — you're good to bake.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            Label("Completed", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
        }
    }

    private func formattedDuration(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        let totalMinutes = Int(minutes.rounded())
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }

    @ViewBuilder
    private func peakedContent(_ step: RevivalFeedStep) -> some View {
        Button {} label: {
            Label(peakDurationLabel(step), systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.green)
        .disabled(true)

        if let nextStep = nextStep(after: step) {
            if bakeReady == false {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.orange)
                    Text("Getting stronger — one more feed.")
                        .font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.10))
                )
            }
        } else {
            doublingQuestion(step)
        }

        if let nextStep = nextStep(after: step) {
            Divider()
                .padding(.vertical, 4)

            if let title = nextStep.instructionTitle, !title.isEmpty {
                Text(title)
                    .font(.title3.bold())
            }

            let isWaiting = nextStep.scheduledTime > Date()

            nextStepScheduleRow(nextStep)

            gramsPanel(nextStep)

            if isWaiting {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Expected wait after feeding: \(nextStep.instructionExpectedWait ?? "")")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                nextStepActionButton(nextStep)

                if let bulletsText = nextStep.instructionBody, !bulletsText.isEmpty {
                    DisclosureGroup("View instructions") {
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else {
                if let bulletsText = nextStep.instructionBody, !bulletsText.isEmpty {
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

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Expected wait: \(nextStep.instructionExpectedWait ?? "")")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                nextStepActionButton(nextStep)
            }
        }
    }

    private func doublingQuestion(_ step: RevivalFeedStep) -> some View {
        VStack(spacing: 6) {
            Text("Did it double?")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    bakeReady = viewModel.evaluateBakeReadiness(
                        step: step,
                        plan: plan,
                        doubled: true,
                        availability: availabilities.first,
                        windows: Array(windows)
                    )
                } label: {
                    Text("Yes, it doubled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    bakeReady = viewModel.evaluateBakeReadiness(
                        step: step,
                        plan: plan,
                        doubled: false,
                        availability: availabilities.first,
                        windows: Array(windows)
                    )
                } label: {
                    Text("No, it didn't")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func nextStepScheduleRow(_ step: RevivalFeedStep) -> some View {
        let now = Date()
        let isFuture = step.scheduledTime > now

        if isFuture {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feed at \(step.scheduledTime, format: .dateTime.weekday(.wide).hour().minute())")
                        .font(.subheadline.bold())
                    RelativeTimeLabel(date: step.scheduledTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func nextStepActionButton(_ step: RevivalFeedStep) -> some View {
        mixFeedButton(step)
    }

    private func nextStep(after step: RevivalFeedStep) -> RevivalFeedStep? {
        sortedSteps.first(where: { $0.sequenceIndex == step.sequenceIndex + 1 })
    }

    private func peakDurationLabel(_ step: RevivalFeedStep) -> String {
        "Peaked in \(formattedDuration(step.timeToPeakMinutes))"
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
            let threshold = max

            if elapsed > threshold {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                        Text(isSevere
                            ? "No clear peak yet — that's normal after long neglect."
                            : "It's been longer than expected. If activity has slowed, move on.")
                            .font(.footnote)
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
                            Text("Feed at \(step.scheduledTime, format: .dateTime.weekday(.wide).hour().minute())")
                                .font(.subheadline.bold())
                            RelativeTimeLabel(date: step.scheduledTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Scheduled for \(step.scheduledTime, format: .dateTime.weekday(.abbreviated).hour().minute())")
                                .font(.footnote)
                            Text("Passed — feed when ready")
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
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Text("You're running late — the next step will shift when you feed.")
                    .font(.footnote)
            }
            .foregroundStyle(.orange)
        } else if step.feedStatus == .inProgress,
                  let startedAt = step.startedAt,
                  let max = step.maxPeakMinutes,
                  now.timeIntervalSince(startedAt) > max * 60
        {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hourglass")
                Text("Peak is slower than expected — that's okay. The next feed will shift.")
                    .font(.footnote)
            }
            .foregroundStyle(.orange)
        }

        overnightPeakCallout(step)
    }

    @ViewBuilder
    private func overnightPeakCallout(_ step: RevivalFeedStep) -> some View {
        if step.feedStatus != .completed, step.feedStatus != .peaked, peakFallsOvernight(step) {
            let peakTime = expectedPeakTime(step)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "moon.zzz")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peak likely around \(peakTime, format: .dateTime.hour().minute()) — while you'd be asleep.")
                        .font(.footnote)
                    Text("Mark peak when you wake up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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



    @ViewBuilder
    private func actionButton(for step: RevivalFeedStep) -> some View {
        mixFeedButton(step)
    }

    private func mixFeedButton(_ step: RevivalFeedStep) -> some View {
        mixButton(step)
            .buttonStyle(.borderedProminent)
    }

    private func mixButton(_ step: RevivalFeedStep) -> some View {
        Button {
            cancelMixReminder(for: step)
            viewModel.markRevivalStepStarted(
                step: step,
                plan: plan,
                availability: availabilities.first,
                windows: Array(windows)
            )
        } label: {
            Text("I've fed the starter")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var upcomingStepsSection: some View {
        let skipThrough = currentStep?.feedStatus == .peaked
            ? plan.currentStepIndex + 1
            : plan.currentStepIndex
        let pending = sortedSteps.filter { $0.sequenceIndex > skipThrough }
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
        let reminderStep: RevivalFeedStep?
        if let step = currentStep, step.feedStatus == .peaked {
            reminderStep = nextStep(after: step)
        } else {
            reminderStep = currentStep
        }
        guard let reminderStep, reminderStep.feedStatus == .pending, reminderStep.scheduledTime > Date() else {
            isReminderPending = false
            return
        }
        let alreadySet = await NotificationService.shared.hasPendingRevivalMixReminder(
            planID: notificationPlanID,
            stepIndex: reminderStep.sequenceIndex
        )
        if !alreadySet {
            await scheduleMixReminder(for: reminderStep)
        }
        isReminderPending = true
    }

    private func bulletLines(_ body: String) -> [String] {
        body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
