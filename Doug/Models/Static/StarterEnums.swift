import Foundation

enum StarterStorageType: String, Codable {
    case fridge
    case counter
}

enum StarterHealthStatus: String, Codable {
    case readyToBake
    case needsFeed
    case needsRevival
}

enum StarterLifecycleState: String, Codable {
    case dormant
    case activating
    case active
    case reviving
}

enum FeedIntent: String, Codable {
    case maintenance
    case activation
    case levain
    case postBake
}
