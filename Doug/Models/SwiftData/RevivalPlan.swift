import Foundation
import SwiftData

/// A multi-day guided starter plan.
///
/// Backs two flows that share the same shape — a sequence of dated feeds, each
/// with its own instruction copy, grams and tolerance band:
///
/// - **Revival** of an existing but neglected starter (`origin == nil`).
/// - **Establishing** a brand-new starter from scratch or another culture
///   (`origin` set to a `StarterOrigin`).
///
/// The type keeps its original name so the persisted store needs no more than a
/// SwiftData lightweight migration.
@Model
final class RevivalPlan {
    var status: String
    var startDate: Date
    var estimatedBakeReadyDate: Date?

    /// `StarterOrigin` rawValue when this plan builds a new starter.
    /// `nil` means it revives an existing one.
    var origin: String?
    /// `StarterEstablishPhase` rawValue. Only meaningful for new-starter plans.
    var currentPhase: String?
    /// The step count the plan was generated with, before any extensions.
    /// Used for honest "Day 3 of ~10" copy.
    var targetStepCount: Int?
    /// How many consecutive readiness feeds have doubled inside their window.
    var consecutiveDoubles: Int = 0
    /// `EstablishNotice` rawValue for the last check-in, so the explanation
    /// the user needs to read outlives navigation and app relaunches.
    var lastNotice: String?

    var initialStarterGrams: Double?
    var flourType: String?
    var kitchenTemperatureCelsius: Double?
    var currentStepIndex: Int = 0
    var assessedNeglect: String?
    var hadHooch: Bool = false
    var daysSinceLastFed: Int?
    var userNotes: String?
    var coachOpeningRead: String?

    @Relationship(deleteRule: .cascade, inverse: \RevivalFeedStep.plan)
    var feedSteps: [RevivalFeedStep] = []

    init() {
        status = RevivalStatus.active.rawValue
        startDate = Date()
    }

    var revivalStatus: RevivalStatus {
        get { RevivalStatus(rawValue: status) ?? .active }
        set { status = newValue.rawValue }
    }

    /// Where this starter came from, or `nil` for a revival of an existing starter.
    var starterOrigin: StarterOrigin? {
        get { origin.flatMap(StarterOrigin.init(rawValue:)) }
        set { origin = newValue?.rawValue }
    }

    /// True when this plan is building a new starter rather than reviving one.
    var isEstablishingNewStarter: Bool {
        starterOrigin != nil
    }

    var establishPhase: StarterEstablishPhase? {
        get { currentPhase.flatMap(StarterEstablishPhase.init(rawValue:)) }
        set { currentPhase = newValue?.rawValue }
    }

    var establishNotice: EstablishNotice? {
        get { lastNotice.flatMap(EstablishNotice.init(rawValue:)) }
        set { lastNotice = newValue?.rawValue }
    }
}

@Model
final class RevivalFeedStep {
    var plan: RevivalPlan?
    var sequenceIndex: Int
    var targetRatioStarter: Int
    var targetRatioFlour: Int
    var targetRatioWater: Int
    var scheduledTime: Date
    var expectedPeakMinutes: Double
    var status: String
    var notificationIdentifier: String?

    var retainStarterGrams: Double?
    var addFlourGrams: Double?
    var addWaterGrams: Double?
    var startedAt: Date?
    var peakTimestamp: Date?
    var timeToPeakMinutes: Double?
    var minPeakMinutes: Double?
    var maxPeakMinutes: Double?
    var originalScheduledTime: Date?

    var instructionTitle: String?
    var instructionBody: String?
    var instructionWatchFor: String?
    var instructionExpectedWait: String?
    var instructionPeakGuidance: String?

    /// `StarterStepKind` rawValue. Defaults to the original revival-feed behaviour
    /// so existing rows migrate unchanged.
    var stepKind: String = StarterStepKind.revivalFeed.rawValue
    /// Whether this step asks the user to watch for and mark a peak. Early
    /// new-starter steps set this false — nothing will rise yet.
    var expectsPeak: Bool = true
    /// Which day of the plan this step belongs to, for "Day 3 of ~10" copy.
    var dayNumber: Int?
    /// `StarterEstablishPhase` rawValue this step was generated for. Lets the
    /// plan skip the rest of a phase when the starter gets ahead of schedule.
    var phase: String?
    /// The user's answers to this step's check-in, encoded by `StarterCheckInSignals`.
    var checkInSignals: String?

    init(
        sequenceIndex: Int,
        scheduledTime: Date,
        expectedPeakMinutes: Double,
        targetRatioStarter: Int = 1,
        targetRatioFlour: Int = 2,
        targetRatioWater: Int = 2
    ) {
        self.sequenceIndex = sequenceIndex
        self.scheduledTime = scheduledTime
        self.expectedPeakMinutes = expectedPeakMinutes
        self.targetRatioStarter = targetRatioStarter
        self.targetRatioFlour = targetRatioFlour
        self.targetRatioWater = targetRatioWater
        status = RevivalFeedStatus.pending.rawValue
    }

    var feedStatus: RevivalFeedStatus {
        get { RevivalFeedStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    var establishPhase: StarterEstablishPhase? {
        get { phase.flatMap(StarterEstablishPhase.init(rawValue:)) }
        set { phase = newValue?.rawValue }
    }

    var starterStepKind: StarterStepKind {
        get { StarterStepKind(rawValue: stepKind) ?? .revivalFeed }
        set {
            stepKind = newValue.rawValue
            expectsPeak = newValue.expectsPeak
        }
    }

    /// The check-in the user recorded for this step, if any.
    var recordedSignals: StarterCheckInSignals? {
        get { checkInSignals.flatMap(StarterCheckInSignals.init(encoded:)) }
        set { checkInSignals = newValue?.encoded }
    }
}

enum RevivalStatus: String, Codable {
    case active
    case completed
    case cancelled
}

enum RevivalFeedStatus: String, Codable {
    case pending
    case inProgress
    case peaked
    case completed
}
