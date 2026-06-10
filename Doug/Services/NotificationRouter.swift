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
        case schedule, starter, history, settings
    }

    /// Starter-tab work requested from a notification. StarterViewModel is
    /// recreated with the tab, so StarterTab consumes this directly (on appear
    /// and on change) rather than via view-model registration.
    enum PendingStarterAction: Equatable {
        case logFeed
    }

    var selectedTab: Tab = .schedule

    /// Set by "Bake again" in History to ask the Schedule tab to start planning a
    /// recipe. The Schedule tab consumes and clears it.
    var pendingPlanRecipeID: RecipeID?

    var pendingStarterAction: PendingStarterAction?

    private weak var scheduleViewModel: ScheduleViewModel?
    private var bufferedFoldEntry: PendingFoldEntry?
    private var bufferedStepDetail: PendingStepDetail?
    private var bufferedBakeDone: PendingStepDetail?

    /// Internal (not private) so tests can exercise fresh instances; production
    /// code uses `shared`.
    init() {}

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
        if let buffered = bufferedBakeDone {
            // Registration happens in ScheduleViewModel.init, before
            // activeSchedule is restored — the view model drains this once
            // restoreActiveSchedule has a schedule to search.
            viewModel.pendingBakeDone = buffered
            bufferedBakeDone = nil
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

    func markBakeSubStepDone(stepTypeID: String, sequenceIndex: Int) {
        selectedTab = .schedule
        let entry = PendingStepDetail(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
        if let viewModel = scheduleViewModel {
            viewModel.pendingBakeDone = entry
            viewModel.consumePendingBakeDone()
        } else {
            bufferedBakeDone = entry
        }
    }

    func focusScheduleTab() {
        selectedTab = .schedule
    }

    func focusStarterTab() {
        selectedTab = .starter
    }

    /// Switches to the Starter tab and asks it to open the log-feed sheet.
    func requestStarterLogFeed() {
        selectedTab = .starter
        pendingStarterAction = .logFeed
    }

    /// Switches to the Schedule tab and requests the plan flow for `recipeID`.
    func requestPlanBake(recipeID: RecipeID) {
        pendingPlanRecipeID = recipeID
        selectedTab = .schedule
    }
}
