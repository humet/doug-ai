import Charts
import SwiftUI

/// Displays a temperature curve and degree-hour progress during active bulk ferment.
///
/// Shows each fold reading as a data point on a line chart, with a RuleMark
/// at the target degree-hour threshold.
struct DegreeHoursChartView: View {
    let readings: [DoughTemperatureReading]
    let targetDegreeHours: Double

    private var sortedReadings: [DoughTemperatureReading] {
        readings.sorted { $0.timestamp < $1.timestamp }
    }

    private var currentDegreeHours: Double {
        let pairs = sortedReadings.map {
            (timestamp: $0.timestamp, temperatureCelsius: $0.temperatureCelsius)
        }
        return DegreeHourCalculator.accumulatedDegreeHours(readings: pairs)
    }

    private var progress: Double {
        DegreeHourCalculator.progress(
            currentDegreeHours: currentDegreeHours,
            targetDegreeHours: targetDegreeHours
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Degree-hours")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(String(format: "%.1f / %.0f", currentDegreeHours, targetDegreeHours))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .tint(progress >= 1.0 ? .green : .blue)
            }

            // Temperature curve chart
            if sortedReadings.count >= 2 {
                Chart {
                    ForEach(sortedReadings, id: \.timestamp) { reading in
                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Temperature", reading.temperatureCelsius)
                        )
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Temperature", reading.temperatureCelsius)
                        )
                        .symbolSize(30)
                    }

                    // Reference line at initial mix temp
                    if let firstTemp = sortedReadings.first?.temperatureCelsius {
                        RuleMark(y: .value("Mix Temp", firstTemp))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [5, 3]))
                    }
                }
                .chartYAxisLabel("°C")
                .chartXAxis {
                    AxisMarks(values: .automatic) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 180)

            } else if sortedReadings.count == 1 {
                HStack {
                    Label(
                        String(format: "Mix temp: %.1f°C", sortedReadings[0].temperatureCelsius),
                        systemImage: "thermometer.medium"
                    )
                    .font(.subheadline)
                    Spacer()
                    Text("Log more readings to see the curve")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No temperature readings yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground), in: .rect(cornerRadius: 12))
    }
}
