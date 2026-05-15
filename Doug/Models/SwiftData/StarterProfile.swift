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
