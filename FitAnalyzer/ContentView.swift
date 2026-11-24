import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let fit = UTType(importedAs: "com.garmin.fit")
}

struct ContentView: View {
    @Environment(ActivityStore.self) private var store
    @AppStorage("unitSystem") private var units: UnitSystem = .systemDefault

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            List(selection: $store.selection) {
                ForEach(store.activities) { activity in
                    ActivityRow(activity: activity, units: units)
                        .tag(activity.id)
                        .contextMenu {
                            Button("Remove", role: .destructive) { store.remove(activity) }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .overlay {
                if store.activities.isEmpty {
                    Text("No activities")
                        .foregroundStyle(.secondary)
                }
            }
        } detail: {
            if let activity = store.selectedActivity {
                ActivityDetailView(activity: activity, units: units)
                    .id(activity.id)
            } else {
                ContentUnavailableView {
                    Label("Open a FIT File", systemImage: "figure.run")
                } description: {
                    Text("Drop .fit files here, or choose them from disk.")
                } actions: {
                    Button("Open…") { store.isImporting = true }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button("Open", systemImage: "plus") { store.isImporting = true }
                    .help("Open FIT files")
            }
        }
        .fileImporter(isPresented: $store.isImporting, allowedContentTypes: [.fit], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { store.open(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let fits = urls.filter { $0.pathExtension.lowercased() == "fit" }
            store.open(fits)
            return !fits.isEmpty
        }
        .alert("Couldn't Open File", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct ActivityRow: View {
    let activity: Activity
    let units: UnitSystem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: activity.sport.symbol)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let start = activity.startTime {
            parts.append(start.formatted(date: .abbreviated, time: .omitted))
        }
        if let distance = activity.distance, distance > 0 {
            parts.append(units.distance(distance))
        }
        return parts.isEmpty ? activity.sport.name : parts.joined(separator: " · ")
    }
}

#Preview {
    ContentView()
        .environment(ActivityStore())
}
