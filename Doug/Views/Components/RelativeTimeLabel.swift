import SwiftUI

/// Renders a relative-time label that says "in 5 min" / "5 min ago" (auto-updating).
///
/// SwiftUI's built-in `Text(date, style: .relative)` shows an absolute-value
/// countdown like "5 min" with no tense — ambiguous once the date passes.
/// This helper wraps `Date.RelativeFormatStyle(presentation: .numeric)` in a
/// `TimelineView` so the label updates without forcing the parent view to
/// rebuild.
struct RelativeTimeLabel: View {
    let date: Date
    var unitsStyle: Date.RelativeFormatStyle.UnitsStyle = .abbreviated
    var interval: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { _ in
            Text(
                date.formatted(
                    .relative(presentation: .numeric, unitsStyle: unitsStyle)
                )
            )
        }
    }
}
