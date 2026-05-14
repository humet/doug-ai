import SwiftUI

enum DougTheme {
    // MARK: - Background Colors (warm, muted tones — render well through glass)

    static let backgroundPrimary = Color("BackgroundPrimary", bundle: nil)
    static let backgroundSecondary = Color("BackgroundSecondary", bundle: nil)

    static let warmCream = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1)
            : UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1)
    })
    static let warmParchment = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)
            : UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1)
    })
    static let warmWheat = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.22, green: 0.19, blue: 0.15, alpha: 1)
            : UIColor(red: 0.91, green: 0.87, blue: 0.78, alpha: 1)
    })

    // MARK: - Surface Colors

    static let cardBackground = warmParchment

    // MARK: - Accent Colors

    static let sourdoughBrown = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.78, green: 0.60, blue: 0.40, alpha: 1)
            : UIColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)
    })
    static let crustGold = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.85, green: 0.68, blue: 0.38, alpha: 1)
            : UIColor(red: 0.78, green: 0.60, blue: 0.30, alpha: 1)
    })
    static let flourWhite = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.18, blue: 0.15, alpha: 1)
            : UIColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1)
    })

    // MARK: - Status Colors

    static let stepUpcoming = Color.secondary
    static let stepActive = Color.blue
    static let stepDone = Color.green
    static let stepSkipped = Color.orange

    static let starterReady = Color.green
    static let starterNeedsFeed = Color.orange
    static let starterNeedsRevival = Color.red

    // MARK: - Typography helpers

    static let monospacedDigit = Font.body.monospacedDigit()
}
