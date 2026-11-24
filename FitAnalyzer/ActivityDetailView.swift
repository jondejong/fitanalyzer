import SwiftUI
import Charts
import MapKit

struct ActivityDetailView: View {
    let activity: Activity
    let units: UnitSystem

    @State private var xAxis: XAxis = .time
    @AppStorage("detailTab") private var tab: Tab = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview", intervals = "Intervals"
        var id: String { rawValue }
    }

    enum XAxis: String, CaseIterable, Identifiable {
        case time = "Time", distance = "Distance"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch tab {
            case .overview: overview
            case .intervals: IntervalsView(activity: activity, units: units)
            }
        }
        .navigationTitle(activity.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statGrid
                if activity.hasRoute { RouteMap(samples: activity.samples) }
                charts
                if activity.laps.count > 1 { lapTable }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: activity.sport.symbol)
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.title.bold())
                if let start = activity.startTime {
                    Text(start.formatted(date: .complete, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Stats

    private struct Stat: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    private var stats: [Stat] {
        var result: [Stat] = []
        func add(_ title: String, _ value: String?) {
            if let value { result.append(Stat(title: title, value: value)) }
        }
        add("Distance", activity.distance.map(units.distance))
        add("Moving Time", activity.movingTime.map(formatDuration))
        add("Elapsed Time", activity.elapsedTime.map(formatDuration))
        if activity.sport.isFootSport {
            add("Avg Pace", activity.avgSpeed.map(units.pace))
            add("Best Pace", activity.maxSpeed.map(units.pace))
        } else {
            add("Avg Speed", activity.avgSpeed.map(units.speed))
            add("Max Speed", activity.maxSpeed.map(units.speed))
        }
        add("Elevation Gain", activity.ascent.map(units.elevation))
        add("Elevation Loss", activity.descent.map(units.elevation))
        add("Avg Heart Rate", activity.avgHeartRate.map { String(format: "%.0f bpm", $0) })
        add("Max Heart Rate", activity.maxHeartRate.map { String(format: "%.0f bpm", $0) })
        add("Avg Power", activity.avgPower.map { String(format: "%.0f W", $0) })
        add("Max Power", activity.maxPower.map { String(format: "%.0f W", $0) })
        add("Avg Cadence", activity.avgCadence.map { String(format: "%.0f %@", $0, cadenceUnit) })
        add("Calories", activity.calories.map { String(format: "%.0f kcal", $0) })
        return result
    }

    private var cadenceUnit: String { activity.sport.isFootSport ? "spm" : "rpm" }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(stat.value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Charts

    private var charts: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Charts").font(.title2.bold())
                Spacer()
                Picker("X Axis", selection: $xAxis) {
                    ForEach(XAxis.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if activity.sport.isFootSport {
                MetricChart(title: "Pace", unit: "min/\(units.distanceUnit)", color: .blue, xAxis: xAxis, units: units,
                            points: paceSeries, reversed: true, yLabel: formatPace)
            } else {
                MetricChart(title: "Speed", unit: units.speedUnit, color: .blue, xAxis: xAxis, units: units,
                            points: series { $0.speed.map(units.speedValue) })
            }
            MetricChart(title: "Heart Rate", unit: "bpm", color: .red, xAxis: xAxis, units: units,
                        points: series(\.heartRate))
            MetricChart(title: "Power", unit: "W", color: .purple, xAxis: xAxis, units: units,
                        points: series(\.power))
            MetricChart(title: "Cadence", unit: cadenceUnit, color: .orange, xAxis: xAxis, units: units,
                        points: series(\.cadence))
            MetricChart(title: "Elevation", unit: units.elevationUnit, color: .green, xAxis: xAxis, units: units,
                        points: series(minRange: 2 / units.elevationMeters) { $0.altitude.map { $0 / units.elevationMeters } })
        }
    }

    /// Extracts one metric against the chosen x-axis, averaged into at most ~600 buckets.
    /// Returns nothing when the metric never varies by more than `minRange` (e.g. a
    /// power channel that is all zeros), so the chart is hidden.
    private func series(minRange: Double = 0, _ value: (Sample) -> Double?) -> [ChartPoint] {
        var raw: [(x: Double, y: Double)] = []
        for sample in activity.samples {
            guard let y = value(sample) else { continue }
            switch xAxis {
            case .time:
                raw.append((sample.elapsed / 60, y))
            case .distance:
                if let d = sample.distance { raw.append((d / units.distanceMeters, y)) }
            }
        }
        guard let low = raw.map(\.y).min(), let high = raw.map(\.y).max(), high - low > minRange else { return [] }
        let bucket = max(1, Int((Double(raw.count) / 600).rounded(.up)))
        var points: [ChartPoint] = []
        var i = 0
        while i < raw.count {
            let slice = raw[i..<min(i + bucket, raw.count)]
            let n = Double(slice.count)
            points.append(ChartPoint(id: points.count,
                                     x: slice.reduce(0) { $0 + $1.x } / n,
                                     y: slice.reduce(0) { $0 + $1.y } / n))
            i += bucket
        }
        return points
    }

    /// Pace in minutes per km/mile, derived from bucket-averaged speed. Stops and
    /// very slow stretches are capped at twice the median pace so they don't
    /// flatten the rest of the chart.
    private var paceSeries: [ChartPoint] {
        let paces = series(\.speed).compactMap { point -> ChartPoint? in
            guard point.y > 0 else { return nil }
            return ChartPoint(id: point.id, x: point.x, y: units.distanceMeters / point.y / 60)
        }
        guard !paces.isEmpty else { return [] }
        let cap = paces.map(\.y).sorted()[paces.count / 2] * 2
        return paces.map { ChartPoint(id: $0.id, x: $0.x, y: min($0.y, cap)) }
    }

    private func formatPace(_ minutes: Double) -> String {
        let seconds = Int((minutes * 60).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Laps

    private var lapTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Laps").font(.title2.bold())
            Grid(alignment: .trailing, horizontalSpacing: 28, verticalSpacing: 8) {
                GridRow {
                    Text("Lap")
                    Text("Time")
                    Text("Distance")
                    Text(activity.sport.isFootSport ? "Pace" : "Speed")
                    Text("Avg HR")
                    Text("Avg Power")
                    Text("Ascent")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(activity.laps) { lap in
                    GridRow {
                        Text("\(lap.id)")
                        Text(lap.time.map(formatDuration) ?? "–")
                        Text(lap.distance.map(units.distance) ?? "–")
                        Text(lap.avgSpeed.map(activity.sport.isFootSport ? units.pace : units.speed) ?? "–")
                        Text(lap.avgHeartRate.map { String(format: "%.0f bpm", $0) } ?? "–")
                        Text(lap.avgPower.map { String(format: "%.0f W", $0) } ?? "–")
                        Text(lap.ascent.map(units.elevation) ?? "–")
                    }
                    .monospacedDigit()
                }
            }
        }
    }
}

struct ChartPoint: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}

private struct MetricChart: View {
    let title: String
    let unit: String
    let color: Color
    let xAxis: ActivityDetailView.XAxis
    let units: UnitSystem
    let points: [ChartPoint]
    /// Draws larger values lower, so a faster pace sits higher.
    var reversed = false
    var yLabel: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }

    var body: some View {
        if points.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(title) (\(unit))")
                    .font(.headline)
                Chart(points) { point in
                    LineMark(x: .value(xAxis.rawValue, point.x), y: .value(title, point.y))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: reversed))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let y = value.as(Double.self) { Text(yLabel(y)) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let x = value.as(Double.self) {
                                switch xAxis {
                                case .time:
                                    // x is in minutes; show h:mm
                                    Text(String(format: "%d:%02d", Int(x) / 60, Int(x) % 60))
                                case .distance:
                                    Text("\(x.formatted(.number.precision(.fractionLength(0...1)))) \(units.distanceUnit)")
                                }
                            }
                        }
                    }
                }
                .frame(height: 170)
            }
        }
    }
}

private struct RouteMap: View {
    let samples: [Sample]

    var body: some View {
        let coordinates = route
        Map {
            MapPolyline(coordinates: coordinates)
                .stroke(.orange, lineWidth: 3)
            if let first = coordinates.first {
                Marker("Start", systemImage: "flag", coordinate: first).tint(.green)
            }
            if let last = coordinates.last {
                Marker("Finish", systemImage: "flag.checkered", coordinate: last).tint(.red)
            }
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// The track thinned to at most ~2000 points.
    private var route: [CLLocationCoordinate2D] {
        let all = samples.compactMap(\.coordinate)
        let step = max(1, all.count / 2000)
        var result = stride(from: 0, to: all.count, by: step).map { all[$0] }
        if let last = all.last, step > 1 { result.append(last) }
        return result
    }
}
