import Foundation

/// Represents a concrete time block where hands-on work cannot happen.
struct UnavailableBlock {
    let start: Date
    let end: Date
}

/// Merges daily available hours and unavailable windows into concrete
/// UnavailableBlock instances for a given date range.
///
/// The scheduler consumes this normalized format rather than dealing with
/// recurring windows, one-off windows, and daily hours separately.
enum AvailabilityResolver {
    /// Generates all unavailable blocks within a date range.
    ///
    /// The result includes:
    /// 1. Outside-daily-hours blocks (before start, after end) for each day
    /// 2. Recurring unavailable windows that match each day
    /// 3. One-off unavailable windows within the range
    ///
    /// - Parameters:
    ///   - from: Start of the date range to resolve.
    ///   - to: End of the date range to resolve.
    ///   - availability: The user's daily available hours.
    ///   - windows: The user's unavailable windows.
    ///   - calendar: Calendar for date calculations.
    /// - Returns: Sorted array of unavailable blocks, merged where overlapping.
    static func resolve(
        from startDate: Date,
        to endDate: Date,
        availability: AvailabilityInput,
        windows: [WindowInput],
        calendar: Calendar = .current
    ) -> [UnavailableBlock] {
        var blocks: [UnavailableBlock] = []

        // Enumerate each day in the range
        var currentDay = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: endDate)

        while currentDay <= lastDay {
            // 1. Outside daily hours — before start
            let dayStart = currentDay
            let availableStart = calendar.date(
                bySettingHour: availability.startHour,
                minute: availability.startMinute,
                second: 0,
                of: currentDay
            ) ?? currentDay

            if dayStart < availableStart {
                blocks.append(UnavailableBlock(start: dayStart, end: availableStart))
            }

            // 2. Outside daily hours — after end
            let availableEnd = calendar.date(
                bySettingHour: availability.endHour,
                minute: availability.endMinute,
                second: 0,
                of: currentDay
            ) ?? currentDay

            let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay
            if availableEnd < nextDay {
                blocks.append(UnavailableBlock(start: availableEnd, end: nextDay))
            }

            // 3. Recurring and one-off windows for this day
            let weekday = calendar.component(.weekday, from: currentDay)

            for window in windows where window.isActive {
                let matches: Bool = if window.isRecurring {
                    window.daysOfWeek.contains(weekday)
                } else if let specificDate = window.specificDate {
                    calendar.isDate(specificDate, inSameDayAs: currentDay)
                } else {
                    false
                }

                if matches {
                    let windowStart = calendar.date(
                        bySettingHour: window.startHour,
                        minute: window.startMinute,
                        second: 0,
                        of: currentDay
                    ) ?? currentDay

                    let windowEnd = calendar.date(
                        bySettingHour: window.endHour,
                        minute: window.endMinute,
                        second: 0,
                        of: currentDay
                    ) ?? currentDay

                    if windowStart < windowEnd {
                        blocks.append(UnavailableBlock(start: windowStart, end: windowEnd))
                    }
                }
            }

            currentDay = nextDay
        }

        return mergeOverlapping(blocks.sorted { $0.start < $1.start })
    }

    /// Checks whether a time range overlaps any unavailable block.
    static func overlaps(
        start: Date,
        end: Date,
        blocks: [UnavailableBlock]
    ) -> [UnavailableBlock] {
        blocks.filter { block in
            start < block.end && end > block.start
        }
    }

    /// Checks whether a single moment falls inside any unavailable block.
    static func momentOverlaps(
        _ moment: Date,
        blocks: [UnavailableBlock]
    ) -> [UnavailableBlock] {
        blocks.filter { block in
            moment >= block.start && moment < block.end
        }
    }

    /// Merges overlapping or adjacent blocks into a minimal set.
    private static func mergeOverlapping(_ sorted: [UnavailableBlock]) -> [UnavailableBlock] {
        guard var current = sorted.first else { return [] }
        var merged: [UnavailableBlock] = []

        for block in sorted.dropFirst() {
            if block.start <= current.end {
                current = UnavailableBlock(
                    start: current.start,
                    end: max(current.end, block.end)
                )
            } else {
                merged.append(current)
                current = block
            }
        }
        merged.append(current)
        return merged
    }
}

// MARK: - Lightweight input types (decoupled from SwiftData)

/// Availability input decoupled from the SwiftData UserAvailability model.
struct AvailabilityInput {
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
}

/// Window input decoupled from the SwiftData UnavailableWindow model.
struct WindowInput {
    let name: String
    let isRecurring: Bool
    let daysOfWeek: [Int]
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let specificDate: Date?
    let isActive: Bool

    init(
        name: String,
        isRecurring: Bool = true,
        daysOfWeek: [Int] = [],
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        specificDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.name = name
        self.isRecurring = isRecurring
        self.daysOfWeek = daysOfWeek
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.specificDate = specificDate
        self.isActive = isActive
    }
}

// MARK: - Convenience conversions from SwiftData models

extension AvailabilityInput {
    init(from model: UserAvailability) {
        startHour = model.dailyStartHour
        startMinute = model.dailyStartMinute
        endHour = model.dailyEndHour
        endMinute = model.dailyEndMinute
    }
}

extension WindowInput {
    init(from model: UnavailableWindow) {
        name = model.name
        isRecurring = model.isRecurring
        daysOfWeek = model.daysOfWeek
        startHour = model.startHour
        startMinute = model.startMinute
        endHour = model.endHour
        endMinute = model.endMinute
        specificDate = model.specificDate
        isActive = model.isActive
    }
}
