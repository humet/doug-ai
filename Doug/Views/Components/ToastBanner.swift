import SwiftUI

/// Brief non-blocking confirmation capsule ("Starter feed logged"). Shown via
/// an overlay and dismissed by the owner after a short delay — it never
/// intercepts touches.
struct ToastBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .capsule)
            .overlay(
                Capsule().strokeBorder(.green.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isStaticText)
    }
}
