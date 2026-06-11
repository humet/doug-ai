import Foundation
import SwiftData

/// Executes Live Activity button intents in the app process.
///
/// A button tap can background-launch the app, in which case no view exists
/// and `ScheduleViewModel` was never created — the work must run directly
/// against the shared store. When the app is already up, the registered view
/// model handles it so in-memory state stays consistent.
@MainActor
enum LiveActivityIntentRunner {
    /// The app's shared container, assigned at launch.
    static var modelContainer: ModelContainer?

    static func completeBakePhase(
        stepTypeID: String,
        sequenceIndex: Int,
        router: NotificationRouter? = nil,
        modelContext: ModelContext? = nil
    ) {
        let router = router ?? .shared
        if router.hasRegisteredViewModel {
            router.markBakeSubStepDone(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
            return
        }

        // A fresh context over the shared store: `markStepDone` saves
        // explicitly, and the UI's main context re-fetches on foreground.
        guard let context = modelContext ?? modelContainer.map({ ModelContext($0) })
        else { return }
        let descriptor = FetchDescriptor<Schedule>(
            predicate: #Predicate { $0.status == "active" }
        )
        guard let schedule = try? context.fetch(descriptor).first else { return }

        let allSteps = schedule.steps + schedule.steps.flatMap(\.subSteps)
        guard let step = allSteps.first(where: {
            $0.stepTypeID == stepTypeID && $0.sequenceIndex == sequenceIndex
        }), step.stepStatus == .active || step.stepStatus == .upcoming else { return }

        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule
        viewModel.markStepDone(step, modelContext: context)
    }
}
