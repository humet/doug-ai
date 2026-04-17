import SwiftUI

/// Stable SF Symbol name + tint for each `StepTypeID`.
enum StepTypeIcon {
    static func systemName(for id: StepTypeID) -> String {
        switch id {
        case .buildLevain: "bubbles.and.sparkles"
        case .autolyse: "drop.halffull"
        case .mix: "hand.point.up.braille"
        case .bulkFerment: "thermometer.sun"
        case .stretchAndFold: "hand.raised.fingers.spread"
        case .addInclusions: "leaf"
        case .shape: "circle.circle"
        case .coldRetard: "snowflake"
        case .preheat: "flame"
        case .bakeCovered: "oven"
        case .bakeUncovered: "oven.fill"
        }
    }

    static func tint(for id: StepTypeID) -> Color {
        switch id {
        case .buildLevain, .mix, .stretchAndFold, .addInclusions, .shape:
            DougTheme.sourdoughBrown
        case .autolyse, .bulkFerment:
            DougTheme.crustGold
        case .coldRetard:
            .blue
        case .preheat, .bakeCovered, .bakeUncovered:
            .orange
        }
    }
}

struct StepTypeIconView: View {
    let stepTypeID: StepTypeID
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: StepTypeIcon.systemName(for: stepTypeID))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(StepTypeIcon.tint(for: stepTypeID))
            .frame(width: size * 1.4, height: size * 1.4)
    }
}
