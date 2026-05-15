import Foundation

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

extension StarterProfileInput {
    init(from model: StarterProfile) {
        storageType = model.starterStorageType
        maintenanceCycleDays = model.maintenanceCycleDays
        needsFeedDaysThreshold = model.needsFeedDaysThreshold
        needsRevivalDaysThreshold = model.needsRevivalDaysThreshold
        averageTimeToPeakMinutes = model.averageTimeToPeakMinutes
        lifecycleState = model.starterLifecycleState
        activePeakAverageMinutes = model.activePeakAverageMinutes
    }
}

extension FeedLogInput {
    init(from model: StarterFeedLog) {
        timestamp = model.timestamp
        ratioStarter = model.ratioStarter
        ratioFlour = model.ratioFlour
        ratioWater = model.ratioWater
        flourType = model.flourType
        kitchenTemperatureCelsius = model.kitchenTemperatureCelsius
        timeToPeakMinutes = model.timeToPeakMinutes
        feedIntent = model.starterFeedIntent
    }
}
