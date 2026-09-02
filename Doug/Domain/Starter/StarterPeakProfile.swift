import Foundation

/// Ratio buckets for feed logs. Each bucket normalises 1:N:N feeds where the
/// flour and water parts are equal — the common maintenance pattern.
enum FeedRatioBucket: String, CaseIterable {
    case oneToOne // 1:1:1
    case oneToTwo // 1:2:2
    case oneToFive // 1:5:5
    case oneToTen // 1:10:10

    static func bucket(starter: Int, flour: Int, water: Int) -> FeedRatioBucket? {
        guard starter > 0, flour == water else { return nil }
        let scale = Double(flour) / Double(starter)
        switch scale {
        case 0.5 ..< 1.5: return .oneToOne
        case 1.5 ..< 3.5: return .oneToTwo
        case 3.5 ..< 7.5: return .oneToFive
        case 7.5...: return .oneToTen
        default: return nil
        }
    }

    /// The starter:flour:water parts for building a levain at this ratio.
    var buildRatio: (starter: Int, flour: Int, water: Int) {
        switch self {
        case .oneToOne: (1, 1, 1)
        case .oneToTwo: (1, 2, 2)
        case .oneToFive: (1, 5, 5)
        case .oneToTen: (1, 10, 10)
        }
    }

    /// Short baker-facing label for an adaptively-chosen build, relative to the
    /// standard 1:5:5. nil for the standard ratio (shown without embellishment).
    var adaptiveBuildLabel: String? {
        switch self {
        case .oneToOne, .oneToTwo: "Quick levain"
        case .oneToFive: nil
        case .oneToTen: "Overnight levain"
        }
    }
}

enum TemperatureBracket: String, CaseIterable {
    case cool // <22°C
    case moderate // 22–25°C
    case warm // 26°C+

    static func bracket(celsius: Double) -> TemperatureBracket {
        switch celsius {
        case ..<22: .cool
        case 22 ..< 26: .moderate
        default: .warm
        }
    }
}

/// Personalised time-to-peak averages derived from feed history,
/// bucketed by ratio and kitchen-temperature bracket.
struct StarterPeakProfile {
    static let minimumSamples = 3

    /// Plausible bounds for a single logged time-to-peak (minutes).
    ///
    /// A levain peaks in hours; even a sluggish, cool starter is comfortably under
    /// two days. Readings outside this band are logging artifacts — e.g. a peak
    /// marked days after the feed, or a negative interval — and must be excluded so
    /// one bad entry can't corrupt schedule estimates. A single 28,720-minute
    /// (~20-day) reading once averaged a bucket up to ~7 days, which made every
    /// bake show zero available start times.
    static let plausibleTimeToPeakRange: ClosedRange<Double> = 30 ... (48 * 60)

    static func isPlausibleTimeToPeak(_ minutes: Double) -> Bool {
        plausibleTimeToPeakRange.contains(minutes)
    }

    private let samplesByBucket: [BucketKey: [Double]]

    private struct BucketKey: Hashable {
        let ratio: FeedRatioBucket
        let bracket: TemperatureBracket
    }

    init(feedLogs: [FeedLogInput], intentFilter: FeedIntent? = nil) {
        var grouped: [BucketKey: [Double]] = [:]
        for log in feedLogs {
            if let filter = intentFilter, log.feedIntent != filter { continue }
            guard let minutes = log.timeToPeakMinutes, Self.isPlausibleTimeToPeak(minutes) else { continue }
            guard let ratio = FeedRatioBucket.bucket(
                starter: log.ratioStarter,
                flour: log.ratioFlour,
                water: log.ratioWater
            ) else { continue }
            let bracket = TemperatureBracket.bracket(celsius: log.kitchenTemperatureCelsius)
            grouped[BucketKey(ratio: ratio, bracket: bracket), default: []].append(minutes)
        }
        samplesByBucket = grouped
    }

    /// Returns the average time-to-peak (minutes) for the bucket, or nil when
    /// the bucket has fewer than `minimumSamples` observations.
    func averageMinutes(ratio: FeedRatioBucket, tempBracket: TemperatureBracket) -> Double? {
        let values = samplesByBucket[BucketKey(ratio: ratio, bracket: tempBracket)] ?? []
        guard values.count >= Self.minimumSamples else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func averageHours(ratio: FeedRatioBucket, tempBracket: TemperatureBracket) -> Double? {
        averageMinutes(ratio: ratio, tempBracket: tempBracket).map { $0 / 60.0 }
    }

    func sampleCount(ratio: FeedRatioBucket, tempBracket: TemperatureBracket) -> Int {
        samplesByBucket[BucketKey(ratio: ratio, bracket: tempBracket)]?.count ?? 0
    }
}

// MARK: - Typical rise (display + diagnostic)

extension StarterPeakProfile {
    /// Above this, a typical rise reads as "unusually long" — a nudge to review the
    /// feed history or starter health. A healthy room-temperature levain peaks well
    /// under this.
    static let unusuallyLongRiseMinutes: Double = 16 * 60 // 16h

    /// What to show the user for "how long does my starter take to peak?".
    enum TypicalRise: Equatable {
        /// `minutes` is the bucket average; `bracket` is the temperature band it
        /// came from; `matchesCurrentTemp` is true when that band matches the
        /// temperature passed in (so the figure reflects current conditions).
        case known(minutes: Double, bracket: TemperatureBracket, matchesCurrentTemp: Bool)
        case insufficientData
    }

    /// Best-available typical rise for a ratio. Prefers the bracket nearest the most
    /// recent feed's temperature; otherwise falls back to the bracket with the most
    /// samples. Always labelled with the band it came from, so it never blends
    /// temperatures into a misleading single number.
    func typicalRise(ratio: FeedRatioBucket, nearTemperatureCelsius: Double?) -> TypicalRise {
        if let temp = nearTemperatureCelsius {
            let bracket = TemperatureBracket.bracket(celsius: temp)
            if let avg = averageMinutes(ratio: ratio, tempBracket: bracket) {
                return .known(minutes: avg, bracket: bracket, matchesCurrentTemp: true)
            }
        }

        let best = TemperatureBracket.allCases
            .map { (bracket: $0, count: sampleCount(ratio: ratio, tempBracket: $0)) }
            .filter { $0.count >= Self.minimumSamples }
            .max { $0.count < $1.count }

        guard let best, let avg = averageMinutes(ratio: ratio, tempBracket: best.bracket) else {
            return .insufficientData
        }
        return .known(minutes: avg, bracket: best.bracket, matchesCurrentTemp: false)
    }
}
