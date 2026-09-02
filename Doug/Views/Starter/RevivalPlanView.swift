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
    @Query var availabilities: [UserAvailability]
    @Query var windows: [UnavailableWindow]
    @Query var profiles: [StarterProfile]
    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    @Environment(\.dismiss) private var dismiss

    @State var viewModel = StarterViewModel()
    @State private var isReminderPending = false
    @State private var bakeReady: Bool?
    @State private var showCoachChat = false
    @State var checkInStep: RevivalFeedStep?

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
                    if plan.isEstablishingNewStarter {
                        Button("Cancel New Starter", role: .destructive) {
                            viewModel.cancelNewStarter(plan: plan, profile: profiles.first)
                        }
                    } else {
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
        }
        .navigationTitle(plan.isEstablishingNewStarter ? "New Starter" : "Revival")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCoachChat = true
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                }
                .accessibilityLabel("Coach")
            }
        }
        // Presented by a Bool, not by `.sheet(item:)`. A newly inserted model's
        // persistentModelID changes when SwiftData saves, and item-based
        // presentation keys off that id — an autosave mid-form would recreate
        // the sheet and silently wipe the user's answers.
        .sheet(isPresented: Binding(
            get: { checkInStep != nil },
            set: { if !$0 { checkInStep = nil } }
        )) {
            if let step = checkInStep {
                StarterCheckInSheet(step: step) { signals in
                    handleCheckIn(signals, step: step)
                }
            }
        }
        .sheet(isPresented: $showCoachChat) {
            CoachChatView(
                schedule: nil,
                scheduleViewModel: nil,
                initialMessage: revivalCoachPrefill,
                starterProfile: profiles.first,
                feedLogs: Array(feedLogs),
                unavailableWindows: Array(windows),
                revivalPlan: plan
            )
        }
        .task(id: currentStep?.status) {
            await refreshReminderState()
            bakeReady = nil
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        if plan.isEstablishingNewStarter {
            Section {
                newStarterHeader
            }
        } else {
            revivalHeaderSection
        }
    }

    private var revivalHeaderSection: some View {
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
                if plan.isEstablishingNewStarter, plan.establishNotice != nil {
                    outcomeCard
                }

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

    private func pendingContent(_ step: RevivalFeedStep) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let isWaiting = step.scheduledTime > context.date

            scheduledTimeRow(step, now: context.date)

            if isWaiting {
                waitingContent(step)
            } else {
                readyToMixContent(step)
            }
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

                Text("Your starter is waking up")
                    .font(.headline)

                Text(
                    "Doubled in \(formattedDuration(step.timeToPeakMinutes)) — one more counter feed and you'll be bake-ready."
                )
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

    func formattedDuration(_ minutes: Double?) -> String {
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

        if plan.isEstablishingNewStarter {
            establishCheckInPrompt(step)
        } else if let nextStep = nextStep(after: step) {
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

        // A new-starter plan hides the next step until the check-in is in,
        // so the user can't skip past the question that moves the plan on.
        if !plan.isEstablishingNewStarter, let nextStep = nextStep(after: step) {
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
        if plan.isEstablishingNewStarter, !step.expectsPeak {
            establishFeedButton(step)
        } else {
            mixFeedButton(step)
        }
    }

    private func nextStep(after step: RevivalFeedStep) -> RevivalFeedStep? {
        sortedSteps.first(where: { $0.sequenceIndex == step.sequenceIndex + 1 })
    }

    func peakDurationLabel(_ step: RevivalFeedStep) -> String {
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
                    Text(
                        "\(minTime, format: .dateTime.hour().minute()) – \(maxTime, format: .dateTime.hour().minute())"
                    )
                    .font(.subheadline.bold())
                    Spacer()
                    peakWindowBadge(startedAt: startedAt, step: step)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DougTheme.cardBackground)
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
    private func scheduledTimeRow(_ step: RevivalFeedStep, now: Date = Date()) -> some View {
        if step.feedStatus == .pending {
            let isFuture = step.scheduledTime > now
            let minutesPast = now.timeIntervalSince(step.scheduledTime) / 60

            HStack(spacing: 8) {
                if isFuture {
                    Image(systemName: "calendar.badge.clock")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feed at \(step.scheduledTime, format: .dateTime.weekday(.wide).hour().minute())")
                            .font(.subheadline.bold())
                        RelativeTimeLabel(date: step.scheduledTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if minutesPast < 30 {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("Time to feed your starter")
                        .font(.subheadline.bold())
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feed now")
                            .font(.subheadline.bold())
                        Text(
                            "Scheduled for \(step.scheduledTime, format: .dateTime.hour().minute()) — \(Int(minutesPast))min ago"
                        )
                        .font(.caption)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFuture ? Color.accentColor.opacity(0.12) : Color.orange.opacity(0.15))
            )
            .foregroundStyle(isFuture ? Color.accentColor : .orange)
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
            // Zero-weight columns are noise: a rehydration step adds no flour,
            // and the first from-scratch mix has no starter to retain.
            if let retain = step.retainStarterGrams, retain > 0 {
                gramsColumn(label: "Retain", grams: retain)
            }
            if let flour = step.addFlourGrams, flour > 0 {
                gramsColumn(label: "+ Flour", grams: flour)
            }
            if let water = step.addWaterGrams, water > 0 {
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
                .fill(DougTheme.cardBackground)
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
        if plan.isEstablishingNewStarter, !step.expectsPeak {
            establishFeedButton(step)
        } else {
            mixFeedButton(step)
        }
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

    private var revivalCoachPrefill: String {
        let stepNum = plan.currentStepIndex + 1
        let total = sortedSteps.count
        let peakTrend = sortedSteps
            .filter { $0.timeToPeakMinutes != nil }
            .map { "\(Int($0.timeToPeakMinutes!))min" }
            .joined(separator: " → ")
        let trend = peakTrend.isEmpty ? "no peaks recorded yet" : peakTrend
        return "My starter is on step \(stepNum) of \(total) in revival. Peak times: \(trend). Is this normal?"
    }

    // MARK: - Helpers

    var sortedSteps: [RevivalFeedStep] {
        plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    var currentStep: RevivalFeedStep? {
        sortedSteps.first(where: { $0.sequenceIndex == plan.currentStepIndex })
            ?? sortedSteps.last
    }

    @ViewBuilder
    var statusBadge: some View {
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

    func cancelMixReminder(for step: RevivalFeedStep) {
        NotificationService.shared.cancelRevivalMixReminder(
            planID: notificationPlanID,
            stepIndex: step.sequenceIndex
        )
        isReminderPending = false
    }

    private func refreshReminderState() async {
        let reminderStep: RevivalFeedStep? = if let step = currentStep, step.feedStatus == .peaked {
            nextStep(after: step)
        } else {
            currentStep
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
