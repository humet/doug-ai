import SwiftUI

struct DayTimeLabel: View {
    let date: Date
    var referenceDate: Date = Date()

    private var dayPrefix: String? {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return nil
        } else if calendar.isDate(date, inSameDayAs: referenceDate.addingTimeInterval(86400)) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
    }

    var body: some View {
        if let prefix = dayPrefix {
            Text("\(prefix) \(date, style: .time)")
        } else {
            Text(date, style: .time)
        }
    }
}
