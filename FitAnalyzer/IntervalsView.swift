import SwiftUI

/// Lets the user cut an activity into laps by distance, edit them, and compare them.
struct IntervalsView: View {
    let activity: Activity
    let units: UnitSystem

    @Environment(ActivityStore.self) private var store
    @State private var selection = Set<IntervalLap.ID>()
    @State private var showingColumns = false
    /// Raw values of the hidden table columns, comma-separated.
    @AppStorage("intervalHiddenColumns") private var hiddenColumnsRaw = ""

    private var hiddenColumns: Set<String> {
        Set(hiddenColumnsRaw.split(separator: ",").map(String.init))
    }

    private var visibleColumns: [Column] {
        Column.allCases.filter { !hiddenColumns.contains($0.rawValue) }
    }

    private func setColumn(_ column: Column, visible: Bool) {
        var hidden = hiddenColumns
        if visible { hidden.remove(column.rawValue) } else { hidden.insert(column.rawValue) }
        hiddenColumnsRaw = hidden.sorted().joined(separator: ",")
    }

    /// Lap sizes offered, in the current distance unit (miles or kilometres).
    private var lapSizes: [Double] {
        units == .metric ? [0.5, 1, 2, 5, 10] : [0.25, 0.5, 1, 5]
    }

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

            Button("Columns", systemImage: "tablecells") { showingColumns.toggle() }
                .help("Show or hide table columns")
                .popover(isPresented: $showingColumns, arrowEdge: .bottom) { columnPicker }

            Button("Start Over", systemImage: "arrow.counterclockwise") { setSplits([]) }
                .disabled(splits.isEmpty)
                .help("Remove all laps")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    /// Checkboxes for each column. Stays open so several can be changed at once.
    private var columnPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show Columns")
                .font(.headline)
            ForEach(Column.allCases.filter(\.canHide)) { column in
                Toggle(column.title(units), isOn: Binding(
                    get: { !hiddenColumns.contains(column.rawValue) },
                    set: { setColumn(column, visible: $0) }
                ))
                .toggleStyle(.checkbox)
            }
            Divider()
            HStack {
                Button("Show All") { hiddenColumnsRaw = "" }
                    .disabled(hiddenColumns.isEmpty)
                Spacer()
                Button("Done") { showingColumns = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 200)
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
        Table(laps, selection: $selection) {
            TableColumnForEach(visibleColumns) { column in
                TableColumn(column.title(units)) { (lap: IntervalLap) in
                    cell(column, lap: lap, track: track)
                }
                .width(min: column == .lap ? 30 : 50, ideal: column == .lap ? 40 : 100)
            }
        }
        // Rebuild the table when the column set changes so the remaining columns
        // are laid out afresh to fill the width.
        .id(hiddenColumnsRaw)
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

    @ViewBuilder
    private func cell(_ column: Column, lap: IntervalLap, track: IntervalTrack) -> some View {
        switch column {
        case .lap:
            Text("\(lap.id)")
        case .distance:
            TextField("Distance", value: distanceBinding(lap, track: track),
                      format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.plain)
                .labelsHidden()
        case .time:
            Text(formatDuration(lap.time))
        case .avgPace:
            Text(lap.avgSpeed.map(units.pace) ?? "–")
        case .avgSpeed:
            Text(lap.avgSpeed.map(units.speed) ?? "–")
        case .maxPace:
            Text(lap.maxSpeed.map(units.pace) ?? "–")
        case .maxSpeed:
            Text(lap.maxSpeed.map(units.speed) ?? "–")
        case .avgHR:
            Text(heartRate(lap.avgHeartRate))
        case .maxHR:
            Text(heartRate(lap.maxHeartRate))
        case .minHR:
            Text(heartRate(lap.minHeartRate))
        }
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
