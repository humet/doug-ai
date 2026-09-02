import AppIntents

/// Marks the running bake phase done straight from the Live Activity ("Lid
/// Removed" / "Bread Out") without opening the app.
///
/// Compiled into both the app and the widget extension so the widget can
/// construct the button, but `LiveActivityIntent` always performs in the app
/// process — launching it in the background when it isn't running.
struct CompleteBakePhaseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Bake Phase Done"
    static let isDiscoverable = false

    @Parameter(title: "Step Type")
    var stepTypeID: String

    @Parameter(title: "Step Index")
    var sequenceIndex: Int

    init() {}

    init(stepTypeID: String, sequenceIndex: Int) {
        self.stepTypeID = stepTypeID
        self.sequenceIndex = sequenceIndex
    }

    /// Wired by the app at launch. The shared target can't reference the
    /// view-model layer, and the widget extension (which also compiles this
    /// file) never executes the intent.
    @MainActor static var performHandler: ((_ stepTypeID: String, _ sequenceIndex: Int) -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.performHandler?(stepTypeID, sequenceIndex)
        return .result()
    }
}
