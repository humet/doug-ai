import Foundation

/// How neglected the starter is, inferred from user-reported condition.
/// Drives revival feed count and expected peak timings.
enum StarterNeglectLevel: String, Codable {
    case mild
    case moderate
    case severe
}

/// Whether a starter is safe to revive at all, or whether the user should discard and restart.
enum StarterSafetyVerdict: Equatable {
    case safeToRevive(StarterNeglectLevel)
    case discardAndRestart(reason: String)
}

/// What the user sees and reports when assessing their starter.
struct StarterConditionInput: Equatable {
    let daysSinceLastFed: Int?
    let hasHooch: Bool
    let smellsStronglyAcetone: Bool
    let hasBubbles: Bool
    let hasPinkOrangeOrMold: Bool
}

/// Triages the user-reported condition into a safety verdict.
///
/// The mold gate is absolute — nothing else matters when contamination is reported.
/// Otherwise, age and hooch/smell signals are combined into a neglect level.
enum StarterConditionAssessor {
    static func assess(_ input: StarterConditionInput) -> StarterSafetyVerdict {
        if input.hasPinkOrangeOrMold {
            return .discardAndRestart(
                reason: """
                Pink, orange, or fuzzy patches usually mean contamination. \
                Don't feed or bake with this starter — discard the whole jar, \
                clean it well, and start a new starter in a fresh jar.
                """
            )
        }

        let days = input.daysSinceLastFed ?? 0

        if days >= 21 || (input.hasHooch && input.smellsStronglyAcetone) {
            return .safeToRevive(.severe)
        }

        if days >= 7 || input.hasHooch {
            return .safeToRevive(.moderate)
        }

        return .safeToRevive(.mild)
    }
}
