import Foundation

struct LevainContext {
    let fedAt: Date
    let expectedPeakMinutes: Double
    let kitchenTemperatureCelsius: Double

    func remainingMinutes(asOf now: Date = Date()) -> Double {
        let elapsed = now.timeIntervalSince(fedAt) / 60.0
        return max(0, expectedPeakMinutes - elapsed)
    }

    func elapsedMinutes(asOf now: Date = Date()) -> Double {
        now.timeIntervalSince(fedAt) / 60.0
    }

    var hasPeaked: Bool {
        remainingMinutes() <= 0
    }
}
