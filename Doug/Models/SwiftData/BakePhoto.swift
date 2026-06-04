import Foundation
import SwiftData

/// A single photo attached to a finished bake's `BakeFermentationProfile`.
/// Image bytes are kept out of the main store via external storage.
@Model
final class BakePhoto {
    @Attribute(.externalStorage) var imageData: Data = Data()
    var order: Int = 0
    var profile: BakeFermentationProfile?

    init(imageData: Data, order: Int) {
        self.imageData = imageData
        self.order = order
    }
}
