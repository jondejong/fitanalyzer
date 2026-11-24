import SwiftUI
import Charts

/// Per-lap charts. Each lap is a bar as wide as its distance, so intervals and
/// recoveries keep their real proportions along the x-axis.
struct IntervalCharts: View {
    let laps: [IntervalLap]
    let selection: Set<IntervalLap.ID>
    let units: UnitSystem
    let usesPace: Bool

    private var showLabels: Bool { laps.count <= 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if laps.contains(where: { $0.avgSpeed != nil }) { paceChart }
            if laps.contains(where: { $0.avgHeartRate != nil }) { heartRateChart }
        }
    }

    // MARK: Shared geometry

    private func x(_ metres: Double) -> Double { metres / units.distanceMeters }

    /// Bar edges, inset slightly so neighbouring laps don't touch.
    private func edges(_ lap: IntervalLap) -> (start: Double, end: Double) {
        let gap = min(x((laps.last?.end ?? 0)) * 0.0015, x(lap.distance) * 0.2)
        return (x(lap.start) + gap, x(lap.end) - gap)
    }

    private func opacity(_ lap: IntervalLap) -> Double {
        selection.isEmpty || selection.contains(lap.id) ? 1 : 0.3
    }

    private var xAxisMarks: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text("\(v.formatted(.number.precision(.fractionLength(0...2)))) \(units.distanceUnit)")
                }
            }
        }
    }

    // MARK: Pace / speed

    private var overallSpeed: Double? {
        let time = laps.reduce(0) { $0 + $1.time }
        let distance = laps.reduce(0) { $0 + $1.distance }
        return time > 0 ? units.speedValue(distance / time) : nil
    }

    private var paceChart: some View {
        let averages = laps.compactMap(\.avgSpeed).map(units.speedValue)
        let slowest = averages.min() ?? 0, fastest = averages.max() ?? 1
        // Cap the axis so one GPS spike in a lap's max can't flatten the bars.
        let peak = min(laps.compactMap(\.maxSpeed).map(units.speedValue).max() ?? fastest, fastest * 1.5)
        let low = max(0, slowest - max(fastest - slowest, slowest * 0.1) * 0.6)
        let high = max(peak, fastest) * 1.03
        let overall = overallSpeed

        return VStack(alignment: .leading, spacing: 8) {
            Text(usesPace ? "Pace by Lap" : "Speed by Lap").font(.title2.bold())
            Chart {
                ForEach(laps) { lap in
                    if let avg = lap.avgSpeed.map(units.speedValue) {
                        let e = edges(lap)
                        let fast = overall.map { avg >= $0 } ?? true
                        RectangleMark(xStart: .value("Start", e.start), xEnd: .value("End", e.end),
                                      yStart: .value("Base", low), yEnd: .value("Average", avg))
                            .foregroundStyle((fast ? Color.blue : Color.teal).gradient)
                            .cornerRadius(4)
                            .opacity(opacity(lap))
                            .annotation(position: .overlay, alignment: .bottom) {
                                if showLabels {
                                    Text(label(avg))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .fixedSize()
                                        .padding(.bottom, 2)
                                }
                            }
                        if let top = lap.maxSpeed.map(units.speedValue) {
                            RuleMark(xStart: .value("Start", e.start), xEnd: .value("End", e.end),
                                     y: .value("Max", min(top, high)))
                                .foregroundStyle(fast ? Color.blue : Color.teal)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .opacity(opacity(lap) * 0.8)
                        }
                    }
                }
                if let overall {
                    RuleMark(y: .value("Overall", overall))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYScale(domain: low...high)
            .chartYAxis {
                AxisMarks(values: ticks(low: low, high: high)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(label(v)) }
                    }
                }
            }
            .chartXAxis { xAxisMarks }
            .frame(height: 260)

            legend([
                ("Faster than overall average", .blue), ("Slower", .teal),
            ], note: usesPace
                ? "Bars show average pace (taller is faster); the line above each bar is the lap's best pace. Dashed line: overall average."
                : "Bars show average speed; the line above each bar is the lap's max speed. Dashed line: overall average.")
        }
    }

    /// Axis/bar label for a speed in display units: pace (m:ss) for foot sports, else the speed.
    private func label(_ speed: Double) -> String {
        guard usesPace else { return speed.formatted(.number.precision(.fractionLength(0...1))) }
        guard speed > 0 else { return "–" }
        let seconds = Int((3600 / speed).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Round tick values: whole pace steps for foot sports, whole speed steps otherwise.
    private func ticks(low: Double, high: Double) -> [Double] {
        guard high > low, low >= 0 else { return [] }
        if usesPace, low > 0 {
            let fastPace = 3600 / high, slowPace = 3600 / low // seconds per unit
            let step = [5, 10, 15, 30, 60, 120, 300, 600].first { (slowPace - fastPace) / $0 <= 6 } ?? 600
            var result: [Double] = []
            var pace = (fastPace / step).rounded(.up) * step
            while pace <= slowPace {
                result.append(3600 / pace)
                pace += step
            }
            return result
        }
        let step = [0.1, 0.2, 0.5, 1, 2, 5, 10].first { (high - low) / $0 <= 6 } ?? 10
        var result: [Double] = []
        var value = (low / step).rounded(.up) * step
        while value <= high {
            result.append(value)
            value += step
        }
        return result
    }

    // MARK: Heart rate

    private var heartRateChart: some View {
        let lows = laps.compactMap(\.minHeartRate), highs = laps.compactMap(\.maxHeartRate)
        let low = max(0, (lows.min() ?? 60) - 6), high = (highs.max() ?? 180) + 6

        return VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate by Lap").font(.title2.bold())
            Chart {
                ForEach(laps) { lap in
                    if let avg = lap.avgHeartRate, let lo = lap.minHeartRate, let hi = lap.maxHeartRate {
                        let e = edges(lap)
                        RectangleMark(xStart: .value("Start", e.start), xEnd: .value("End", e.end),
                                      yStart: .value("Min", lo), yEnd: .value("Max", max(hi, lo + 0.5)))
                            .foregroundStyle(Color.red.opacity(0.28))
                            .cornerRadius(4)
                            .opacity(opacity(lap))
                        RuleMark(xStart: .value("Start", e.start), xEnd: .value("End", e.end),
                                 y: .value("Average", avg))
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .opacity(opacity(lap))
                            .annotation(position: .top, spacing: 2) {
                                if showLabels {
                                    Text(String(format: "%.0f", avg))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.red)
                                        .fixedSize()
                                }
                            }
                    }
                }
            }
            .chartYScale(domain: low...high)
            .chartXAxis { xAxisMarks }
            .frame(height: 240)

            legend([], note: "Shaded bars span each lap's min to max heart rate (bpm); the solid line is the average.")
        }
    }

    private func legend(_ items: [(String, Color)], note: String) -> some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(item.1).frame(width: 10, height: 10)
                    Text(item.0)
                }
            }
            Text(note)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
