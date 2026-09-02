import Foundation
import SwiftData

@Model
final class StarterProfile {
    var storageType: String
    var maintenanceCycleDays: Double
    var healthStatus: String
    var lastUpdated: Date

    var needsFeedDaysThreshold: Double
    var needsRevivalDaysThreshold: Double
    var averageTimeToPeakMinutes: Double?

    var lifecycleState: String = StarterLifecycleState.dormant.rawValue
    var stateChangedAt: Date = Date()
    var activePeakAverageMinutes: Double?

    /// False when the user has no starter yet — a fresh install that chose
    /// "not yet", or an existing starter declared dead. Existing rows default
    /// to true, which is correct for anyone already using the app.
    var hasStarter: Bool = true
    /// Bumped each time a new starter is established. Feed logs carry the
    /// generation they belong to so a dead starter's readings can't skew the
    /// new one's averages and scheduling.
    var starterGeneration: Int = 1
    /// When the current generation finished its plan and became usable.
    var starterBornAt: Date?

    init(
        storageType: StarterStorageType = .fridge,
        maintenanceCycleDays: Double = 6
    ) {
        self.storageType = storageType.rawValue
        self.maintenanceCycleDays = maintenanceCycleDays
        healthStatus = StarterHealthStatus.needsFeed.rawValue
        lastUpdated = Date()
        needsFeedDaysThreshold = 7
        needsRevivalDaysThreshold = 10
    }

    var starterStorageType: StarterStorageType {
        get { StarterStorageType(rawValue: storageType) ?? .fridge }
        set { storageType = newValue.rawValue }
    }

    var starterHealthStatus: StarterHealthStatus {
        get { StarterHealthStatus(rawValue: healthStatus) ?? .needsFeed }
        set { healthStatus = newValue.rawValue }
    }

    var starterLifecycleState: StarterLifecycleState {
        get { StarterLifecycleState(rawValue: lifecycleState) ?? .dormant }
        set {
            lifecycleState = newValue.rawValue
            stateChangedAt = Date()
        }
    }
}
