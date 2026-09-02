import Foundation

/// The baker's post-bake reflection, captured in `FinishBakeSheet` and turned
/// into a persisted `BakeFermentationProfile` by `ScheduleViewModel.finishBake`.
/// Scores are 1–5; `0` means the baker left them unrated. Photos are JPEG bytes.
struct BakeReflection {
    var rating: Int = 0
    var crumbOpenness: Int = 0
    var crustColor: Int = 0
    var sourness: Int = 0
    var ovenSpring: Int = 0
    var notes: String = ""
    var photoData: [Data] = []
}
