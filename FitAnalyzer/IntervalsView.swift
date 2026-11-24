import SwiftUI

/// Lets the user cut an activity into laps by distance, edit them, and compare them.
struct IntervalsView: View {
    let activity: Activity
    let units: UnitSystem

    @Environment(ActivityStore.self) private var store
    @State private var selection = Set<IntervalLap.ID>()
    @AppStorage("intervalTableColumns") private var columns: TableColumnCustomization<IntervalLap>

    /// Lap sizes offered, in the current distance unit (miles or kilometres).
    private let lapSizes: [Double] = [0.25, 0.5, 1, 5]

    private var splits: [Double] { store.intervalSplits[activity.id] ?? [] }

    private func setSplits(_ newValue: [Double]) {
        store.intervalSplits[activity.id] = newValue
        selection = []
    }

    var body: some View {
        let track = IntervalTrack(activity)
        let laps = track.laps(splits: splits)

        if laps.isEmpty {
            ContentUnavailableView("No Distance Data", systemImage: "ruler",
                                   description: Text("This activity has no recorded distance to split into laps."))
        } else {
            VStack(spacing: 0) {
                controls(track: track)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        table(laps: laps, track: track)
                        IntervalCharts(laps: laps, selection: selection, units: units,
                                       usesPace: activity.sport.isFootSport)
                    }
                    .padding(24)
                    .frame(maxWidth: 1100, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Controls

    private func controls(track: IntervalTrack) -> some View {
        HStack(spacing: 12) {
            Menu("Create Laps", systemImage: "ruler") {
                ForEach(lapSizes, id: \.self) { size in
                    Button("Every \(sizeLabel(size)) \(units.distanceUnit)") {
                        setSplits(track.splits(every: size * units.distanceMeters))
                    }
                }
                if activity.laps.count > 1 {
                    Divider()
                    Button("Laps Recorded in File") { setSplits(track.splits(from: activity.laps)) }
                }
            }
            .fixedSize()

            Button("Combine", systemImage: "arrow.triangle.merge") { combineSelection(track: track) }
                .disabled(selection.count < 2)
                .keyboardShortcut("j")
                .help("Combine the selected laps into one (⌘J)")

            if splits.isEmpty {
                Text("Choose a lap distance to split this activity.")
                    .foregroundStyle(.secondary)
            } else if selection.count < 2 {
                Text("Select laps to combine them. Double-click a distance to change it.")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu("Columns", systemImage: "tablecells") {
                ForEach(Column.allCases.filter(\.canHide)) { column in
                    Toggle(column.title(units), isOn: Binding(
                        get: { columns[visibility: column.rawValue] != .hidden },
                        set: { columns[visibility: column.rawValue] = $0 ? .visible : .hidden }
                    ))
                }
            }
            .fixedSize()

            Button("Start Over", systemImage: "arrow.counterclockwise") { setSplits([]) }
                .disabled(splits.isEmpty)
                .help("Remove all laps")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func sizeLabel(_ size: Double) -> String {
        size.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Merges everything from the first to the last selected lap.
    private func combineSelection(track: IntervalTrack) {
        guard let first = selection.min(), let last = selection.max(), first < last else { return }
        setSplits(track.combining(splits, laps: first - 1, through: last - 1))
    }

    // MARK: Table

    enum Column: String, CaseIterable, Identifiable {
        case lap, distance, time, avgPace, avgSpeed, maxPace, maxSpeed, avgHR, maxHR, minHR
        var id: String { rawValue }
        var canHide: Bool { self != .lap }

        func title(_ units: UnitSystem) -> String {
            switch self {
            case .lap: return "Lap"
            case .distance: return "Distance (\(units.distanceUnit))"
            case .time: return "Time"
            case .avgPace: return "Avg Pace"
            case .avgSpeed: return "Avg Speed"
            case .maxPace: return "Max Pace"
            case .maxSpeed: return "Max Speed"
            case .avgHR: return "Avg HR"
            case .maxHR: return "Max HR"
            case .minHR: return "Min HR"
            }
        }
    }

    private func table(laps: [IntervalLap], track: IntervalTrack) -> some View {
        Table(laps, selection: $selection, columnCustomization: $columns) {
            Group {
                TableColumn(Column.lap.title(units)) { (lap: IntervalLap) in
                    Text("\(lap.id)")
                }
                .width(min: 30, ideal: 40, max: 60)
                .customizationID(Column.lap.rawValue)
                .disabledCustomizationBehavior(.visibility)

                TableColumn(Column.distance.title(units)) { (lap: IntervalLap) in
                    TextField("Distance", value: distanceBinding(lap, track: track),
                              format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                }
                .customizationID(Column.distance.rawValue)

                TableColumn(Column.time.title(units)) { (lap: IntervalLap) in
                    Text(formatDuration(lap.time))
                }
                .customizationID(Column.time.rawValue)

                TableColumn(Column.avgPace.title(units)) { (lap: IntervalLap) in
                    Text(lap.avgSpeed.map(units.pace) ?? "–")
                }
                .customizationID(Column.avgPace.rawValue)

                TableColumn(Column.avgSpeed.title(units)) { (lap: IntervalLap) in
                    Text(lap.avgSpeed.map(units.speed) ?? "–")
                }
                .customizationID(Column.avgSpeed.rawValue)
            }
            Group {
                TableColumn(Column.maxPace.title(units)) { (lap: IntervalLap) in
                    Text(lap.maxSpeed.map(units.pace) ?? "–")
                }
                .customizationID(Column.maxPace.rawValue)

                TableColumn(Column.maxSpeed.title(units)) { (lap: IntervalLap) in
                    Text(lap.maxSpeed.map(units.speed) ?? "–")
                }
                .customizationID(Column.maxSpeed.rawValue)

                TableColumn(Column.avgHR.title(units)) { (lap: IntervalLap) in
                    Text(heartRate(lap.avgHeartRate))
                }
                .customizationID(Column.avgHR.rawValue)

                TableColumn(Column.maxHR.title(units)) { (lap: IntervalLap) in
                    Text(heartRate(lap.maxHeartRate))
                }
                .customizationID(Column.maxHR.rawValue)

                TableColumn(Column.minHR.title(units)) { (lap: IntervalLap) in
                    Text(heartRate(lap.minHeartRate))
                }
                .customizationID(Column.minHR.rawValue)
            }
        }
        .monospacedDigit()
        .contextMenu(forSelectionType: IntervalLap.ID.self) { ids in
            if ids.count > 1, let first = ids.min(), let last = ids.max() {
                Button("Combine Laps \(first)–\(last)") {
                    setSplits(track.combining(splits, laps: first - 1, through: last - 1))
                }
            }
        }
        .frame(height: CGFloat(min(laps.count, 14)) * 28 + 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }

    private func heartRate(_ value: Double?) -> String {
        value.map { String(format: "%.0f", $0) } ?? "–"
    }

    /// Editing a lap's distance (in display units) moves its end; later laps shift along.
    private func distanceBinding(_ lap: IntervalLap, track: IntervalTrack) -> Binding<Double> {
        Binding(
            get: { lap.distance / units.distanceMeters },
            set: { newValue in
                let metres = newValue * units.distanceMeters
                guard metres > 0, abs(metres - lap.distance) > 0.5 else { return }
                setSplits(track.settingDistance(splits, ofLap: lap.id - 1, to: metres))
            }
        )
    }
}
