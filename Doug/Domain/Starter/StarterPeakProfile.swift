import Foundation

/// Ratio buckets for feed logs. Each bucket normalises 1:N:N feeds where the
/// flour and water parts are equal — the common maintenance pattern.
enum FeedRatioBucket: String, CaseIterable, Sendable {
    case oneToOne    // 1:1:1
    case oneToTwo    // 1:2:2
    case oneToFive   // 1:5:5
    case oneToTen    // 1:10:10

    static func bucket(starter: Int, flour: Int, water: Int) -> FeedRatioBucket? {
        guard starter > 0, flour == water else { return nil }
        let scale = Double(flour) / Double(starter)
        switch scale {
        case 0.5..<1.5:  return .oneToOne
        case 1.5..<3.5:  return .oneToTwo
        case 3.5..<7.5:  return .oneToFive
        case 7.5...:     return .oneToTen
        default:         return nil
        }
    }
}

enum TemperatureBracket: String, CaseIterable, Sendable {
    case cool      // <22°C
    case moderate  // 22–25°C
    case warm      // 26°C+

    static func bracket(celsius: Double) -> TemperatureBracket {
        switch celsius {
        case ..<22:    return .cool
        case 22..<26:  return .moderate
        default:       return .warm
        }
    }
}

/// Personalised time-to-peak averages derived from feed history,
/// bucketed by ratio and kitchen-temperature bracket.
struct StarterPeakProfile: Sendable {
    static let minimumSamples = 3

    private let samplesByBucket: [BucketKey: [Double]]

    private struct BucketKey: Hashable {
        let ratio: FeedRatioBucket
        let bracket: TemperatureBracket
    }

    init(feedLogs: [FeedLogInput]) {
        var grouped: [BucketKey: [Double]] = [:]
        for log in feedLogs {
            guard let minutes = log.timeToPeakMinutes, minutes > 0 else { continue }
            guard let ratio = FeedRatioBucket.bucket(
                starter: log.ratioStarter,
                flour: log.ratioFlour,
                water: log.ratioWater
            ) else { continue }
            let bracket = TemperatureBracket.bracket(celsius: log.kitchenTemperatureCelsius)
            grouped[BucketKey(ratio: ratio, bracket: bracket), default: []].append(minutes)
        }
        self.samplesByBucket = grouped
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
