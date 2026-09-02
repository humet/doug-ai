import Foundation

/// The kitchen and calendar a plan is laid out against.
struct StarterPlanEnvironment {
    let kitchenTempC: Double
    let availability: AvailabilityInput
    let windows: [WindowInput]
    let calendar: Calendar

    init(
        kitchenTempC: Double = StarterOriginPlanner.referenceKitchenTempC,
        availability: AvailabilityInput,
        windows: [WindowInput] = [],
        calendar: Calendar = .current
    ) {
        self.kitchenTempC = kitchenTempC
        self.availability = availability
        self.windows = windows
        self.calendar = calendar
    }
}

/// Everything needed to lay out a plan for a brand-new starter.
struct StarterOriginPlanInput {
    let origin: StarterOrigin
    let startTime: Date
    let flourType: String
    /// Route-dependent starting weight: the first flour weight when building
    /// from scratch, the dried flake weight for a dried culture, or the amount
    /// of live starter received as a gift.
    let seedGrams: Double
    let environment: StarterPlanEnvironment

    init(
        origin: StarterOrigin,
        startTime: Date,
        seedGrams: Double,
        environment: StarterPlanEnvironment,
        flourType: String? = nil
    ) {
        self.origin = origin
        self.startTime = startTime
        self.seedGrams = seedGrams
        self.environment = environment
        self.flourType = flourType ?? StarterOriginPlanner.recommendedFlour(for: origin)
    }
}

/// A request to append more steps to a plan already in progress.
struct StarterPlanExtension {
    /// The step being extended. Grams and ratio are inherited from it so an
    /// extension always feeds the starter exactly as that step did.
    let template: StarterProgramStep
    let count: Int
    /// Defaults to the template's own kind and phase.
    let kind: StarterStepKind?
    let phase: StarterEstablishPhase?
    let startingAt: Date
    let planStartDate: Date

    init(
        template: StarterProgramStep,
        count: Int,
        startingAt: Date,
        planStartDate: Date,
        kind: StarterStepKind? = nil,
        phase: StarterEstablishPhase? = nil
    ) {
        self.template = template
        self.count = count
        self.startingAt = startingAt
        self.planStartDate = planStartDate
        self.kind = kind
        self.phase = phase
    }
}

/// One planned step of a new-starter plan (domain output, not SwiftData).
struct StarterProgramStep: Equatable {
    let sequenceIndex: Int
    /// Day of the plan, counting the start day as 1.
    let dayNumber: Int
    let kind: StarterStepKind
    let phase: StarterEstablishPhase
    let scheduledTime: Date
    /// Whether the user should watch for and mark a peak on this step.
    let expectsPeak: Bool
    /// Time to peak for peak-expecting steps. For steps that expect no peak
    /// this carries the wait until the next step, so the UI always has an
    /// honest "expected wait" to show.
    let expectedPeakMinutes: Double
    let minPeakMinutes: Double?
    let maxPeakMinutes: Double?
    let retainStarterGrams: Double
    let addFlourGrams: Double
    let addWaterGrams: Double
    let ratioStarter: Int
    let ratioFlour: Int
    let ratioWater: Int
}
