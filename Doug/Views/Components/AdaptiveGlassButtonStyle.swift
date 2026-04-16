import SwiftUI

extension View {
    /// Applies a Liquid Glass button style, falling back to a solid bordered
    /// style when Reduce Transparency is enabled.
    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(AdaptiveGlassButtonStyle(prominent: prominent))
    }
}

private struct AdaptiveGlassButtonStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch (reduceTransparency, prominent) {
        case (true, true):
            content.buttonStyle(.borderedProminent)
        case (true, false):
            content.buttonStyle(.bordered)
        case (false, true):
            content.buttonStyle(.glassProminent)
        case (false, false):
            content.buttonStyle(.glass)
        }
    }
}
