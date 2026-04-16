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

    init(
        storageType: StarterStorageType = .fridge,
        maintenanceCycleDays: Double = 6
    ) {
        self.storageType = storageType.rawValue
        self.maintenanceCycleDays = maintenanceCycleDays
        self.healthStatus = StarterHealthStatus.needsFeed.rawValue
        self.lastUpdated = Date()

        switch storageType {
        case .fridge:
            self.needsFeedDaysThreshold = 7
            self.needsRevivalDaysThreshold = 10
        case .counter:
            self.needsFeedDaysThreshold = 1.5
            self.needsRevivalDaysThreshold = 2
        }
    }

    var starterStorageType: StarterStorageType {
        get { StarterStorageType(rawValue: storageType) ?? .fridge }
        set { storageType = newValue.rawValue }
    }

    var starterHealthStatus: StarterHealthStatus {
        get { StarterHealthStatus(rawValue: healthStatus) ?? .needsFeed }
        set { healthStatus = newValue.rawValue }
    }
}

enum StarterStorageType: String, Codable, Sendable {
    case fridge
    case counter
}

enum StarterHealthStatus: String, Codable, Sendable {
    case readyToBake
    case needsFeed
    case needsRevival
}
