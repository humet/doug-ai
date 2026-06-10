import Foundation

/// Lifecycle status of a schedule step. Lives in Models/Static (not next to the
/// `ScheduleStep` @Model) so pure Domain code — which is compiled into the
/// DougDomain package without SwiftData — can reason about step state.
enum StepStatus: String, Codable {
    case upcoming
    case active
    case done
    case skipped
}
