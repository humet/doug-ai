import SwiftUI

/// A floating action button with Liquid Glass styling.
///
/// Falls back to `.borderedProminent` when Reduce Transparency is enabled.
struct GlassActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .adaptiveGlassButtonStyle(prominent: true)
    }
}

#Preview {
    ZStack {
        Color(red: 0.95, green: 0.92, blue: 0.85)
            .ignoresSafeArea()

        VStack {
            Spacer()
            GlassActionButton(title: "Start Bake", systemImage: "flame") {
                // action
            }
        }
        .padding()
    }
}
