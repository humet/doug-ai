import SwiftUI

enum DougTheme {
    // MARK: - Background Colors (warm, muted tones — render well through glass)

    static let backgroundPrimary = Color("BackgroundPrimary", bundle: nil)
    static let backgroundSecondary = Color("BackgroundSecondary", bundle: nil)

    // Fallback colors when asset catalog colors aren't set up yet
    static let warmCream = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let warmParchment = Color(red: 0.95, green: 0.92, blue: 0.85)
    static let warmWheat = Color(red: 0.91, green: 0.87, blue: 0.78)

    // MARK: - Surface Colors

    static let cardBackground = warmParchment

    // MARK: - Accent Colors

    static let sourdoughBrown = Color(red: 0.55, green: 0.38, blue: 0.22)
    static let crustGold = Color(red: 0.78, green: 0.60, blue: 0.30)
    static let flourWhite = Color(red: 0.97, green: 0.95, blue: 0.90)

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
