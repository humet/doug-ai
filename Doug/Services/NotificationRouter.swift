import Foundation
import Observation

struct PendingFoldEntry: Identifiable, Equatable {
    let stepTypeID: String
    let sequenceIndex: Int
    var id: String { "\(stepTypeID)-\(sequenceIndex)" }
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

    private init() {}

    func registerScheduleViewModel(_ viewModel: ScheduleViewModel) {
        scheduleViewModel = viewModel
        if let buffered = bufferedFoldEntry {
            viewModel.pendingFoldEntry = buffered
            bufferedFoldEntry = nil
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

    func focusScheduleTab() {
        selectedTab = .schedule
    }
}
