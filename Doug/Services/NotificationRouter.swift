import Foundation
import Observation
import SwiftData

struct PendingFoldEntry: Identifiable, Equatable {
    let stepTypeID: String
    let sequenceIndex: Int
    var id: String {
        "\(stepTypeID)-\(sequenceIndex)"
    }
}

/// Bridges notification taps (fired outside SwiftUI) into the live ScheduleViewModel
/// and drives tab selection. Buffers signals that arrive before the view model is created.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    enum Tab: Hashable {
        case schedule, starter, calculator, settings
    }

    var selectedTab: Tab = .schedule

    private weak var scheduleViewModel: ScheduleViewModel?
    private var bufferedFoldEntry: PendingFoldEntry?
    private var bufferedStepDetail: PendingStepDetail?
    private var bufferedSnooze: PendingStepDetail?

    private init() {}

    func registerScheduleViewModel(_ viewModel: ScheduleViewModel) {
        scheduleViewModel = viewModel
        if let buffered = bufferedFoldEntry {
            viewModel.pendingFoldEntry = buffered
            bufferedFoldEntry = nil
        }
        if let buffered = bufferedStepDetail {
            viewModel.pendingStepDetail = buffered
            bufferedStepDetail = nil
        }
        if let buffered = bufferedSnooze {
            applySnooze(buffered, on: viewModel)
            bufferedSnooze = nil
        }
    }

    func requestFoldEntry(stepTypeID: String, sequenceIndex: Int) {
        selectedTab = .schedule
        let entry = PendingFoldEntry(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
        if let viewModel = scheduleViewModel {
            viewModel.pendingFoldEntry = entry
        } else {
            bufferedFoldEntry = entry
        }
    }

    func requestStepDetail(stepTypeID: String, sequenceIndex: Int) {
        selectedTab = .schedule
        let entry = PendingStepDetail(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
        if let viewModel = scheduleViewModel {
            viewModel.pendingStepDetail = entry
        } else {
            bufferedStepDetail = entry
        }
    }

    /// Applies a 30-minute snooze to a scheduled step (hands-on or fold) from a notification action.
    /// If the ScheduleViewModel is not yet attached (app was cold-launched), the request buffers
    /// and is applied once the view model registers.
    func snoozeStep(stepTypeID: String, sequenceIndex: Int) {
        let entry = PendingStepDetail(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
        if let viewModel = scheduleViewModel {
            applySnooze(entry, on: viewModel)
        } else {
            bufferedSnooze = entry
        }
    }

    private func applySnooze(_ entry: PendingStepDetail, on viewModel: ScheduleViewModel) {
        guard let schedule = viewModel.activeSchedule else { return }
        let step = findStep(in: schedule, matching: entry)
        guard let step, let context = step.modelContext else { return }
        viewModel.extendStep(step, byMinutes: 30, modelContext: context)
    }

    private func findStep(in schedule: Schedule, matching entry: PendingStepDetail) -> ScheduleStep? {
        let allSteps = schedule.steps + schedule.steps.flatMap(\.subSteps)
        return allSteps.first {
            $0.stepTypeID == entry.stepTypeID && $0.sequenceIndex == entry.sequenceIndex
        }
    }

    func focusScheduleTab() {
        selectedTab = .schedule
    }
}
