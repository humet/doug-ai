import Foundation
import Observation

/// App-wide transient confirmations ("Starter feed logged"). One message at a
/// time, auto-dismissed. Rendered once above the TabView so feedback reaches
/// the user on whichever tab they're on — essential for cross-tab side
/// effects like Starter-tab actions advancing the bake schedule.
@Observable
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    private(set) var message: String?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: Duration = .seconds(2.5)) {
        self.message = message
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
