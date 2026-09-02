import Foundation

enum StarterStateMachine {
    struct TransitionResult {
        let newState: StarterLifecycleState
        let reason: String
    }

    // MARK: - Explicit Transitions

    static func activate(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        switch currentState {
        case .dormant:
            TransitionResult(newState: .activating, reason: "Starter taken out of the fridge to activate")
        case .activating, .active:
            nil
        case .reviving, .establishing:
            nil
        }
    }

    static func refrigerate(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        switch currentState {
        case .activating:
            TransitionResult(newState: .dormant, reason: "Activation cancelled, starter returned to fridge")
        case .active:
            TransitionResult(newState: .dormant, reason: "Starter fed and returned to fridge")
        case .dormant:
            nil
        case .reviving, .establishing:
            nil
        }
    }

    static func startRevival(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        guard currentState == .dormant else { return nil }
        return TransitionResult(newState: .reviving, reason: "Starting revival plan")
    }

    static func completeRevival(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        guard currentState == .reviving else { return nil }
        return TransitionResult(
            newState: .activating,
            reason: "Revival complete — one more counter feed to full strength"
        )
    }

    static func cancelRevival(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        guard currentState == .reviving else { return nil }
        return TransitionResult(newState: .dormant, reason: "Revival cancelled")
    }

    // MARK: - Establishing a New Starter

    /// Begins a plan that creates a starter from scratch or from another culture.
    ///
    /// Allowed from any state: a user whose starter has just died needs this
    /// even while the app still thinks that starter is active or reviving.
    static func startEstablishing(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        guard currentState != .establishing else { return nil }
        return TransitionResult(
            newState: .establishing,
            reason: "Starting a new starter"
        )
    }

    /// A new starter has passed its confirming feeds. It is on the counter and
    /// freshly peaked, so it is ready to bake with — not merely activating.
    static func completeEstablishing(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        guard currentState == .establishing else { return nil }
        return TransitionResult(
            newState: .active,
            reason: "New starter is established and ready to bake"
        )
    }

    static func cancelEstablishing(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        guard currentState == .establishing else { return nil }
        return TransitionResult(newState: .dormant, reason: "New starter cancelled")
    }

    static func markPeakConfirmed(
        currentState: StarterLifecycleState
    ) -> TransitionResult? {
        guard currentState == .activating else { return nil }
        return TransitionResult(
            newState: .active,
            reason: "Starter peak confirmed during bake — ready to build levain"
        )
    }

    // MARK: - Auto Transitions

    static func evaluateAutoTransition(
        currentState: StarterLifecycleState,
        stateChangedAt: Date,
        lastActivationFeed: FeedLogInput?,
        activePeakAverage: Double?,
        now: Date = Date()
    ) -> TransitionResult? {
        switch currentState {
        case .activating:
            return evaluateActivatingTransition(
                lastActivationFeed: lastActivationFeed,
                activePeakAverage: activePeakAverage
            )
        case .active:
            let hoursActive = now.timeIntervalSince(stateChangedAt) / 3600
            if hoursActive > 24 {
                return TransitionResult(
                    newState: .active,
                    reason: "Starter has been active for over 24 hours — feed & refrigerate or build your levain"
                )
            }
            return nil
        case .dormant, .reviving, .establishing:
            return nil
        }
    }

    private static func evaluateActivatingTransition(
        lastActivationFeed: FeedLogInput?,
        activePeakAverage: Double?
    ) -> TransitionResult? {
        guard let feed = lastActivationFeed,
              let peakMinutes = feed.timeToPeakMinutes
        else { return nil }

        if let avg = activePeakAverage {
            if peakMinutes <= avg * 1.2 {
                return TransitionResult(
                    newState: .active,
                    reason: "Starter peaked within expected range — ready to bake"
                )
            }
        } else {
            if peakMinutes <= 480 {
                return TransitionResult(newState: .active, reason: "Starter peaked — ready to bake")
            }
        }

        return nil
    }
}
