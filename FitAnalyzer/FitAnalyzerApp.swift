import SwiftUI

@main
struct FitAnalyzerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ActivityStore.shared

    var body: some Scene {
        Window("FitAnalyzer", id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 1100, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { store.isImporting = true }
                    .keyboardShortcut("o")
            }
        }
    }
}

/// Receives files opened from Finder, the Dock icon or `open -a`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        ActivityStore.shared.open(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
@Observable
final class ActivityStore {
    static let shared = ActivityStore()

    var activities: [Activity] = []
    var selection: Activity.ID?
    var isImporting = false
    /// User-defined lap boundaries per activity, in metres from the start. Not saved to disk.
    var intervalSplits: [Activity.ID: [Double]] = [:]
    var errorMessage: String?

    var selectedActivity: Activity? {
        activities.first { $0.id == selection }
    }

    func open(_ urls: [URL]) {
        Task {
            for url in urls {
                do {
                    let activity = try await Task.detached(priority: .userInitiated) {
                        try Activity.load(from: url)
                    }.value
                    activities.append(activity)
                    selection = activity.id
                } catch {
                    errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }

    func remove(_ activity: Activity) {
        activities.removeAll { $0.id == activity.id }
        intervalSplits[activity.id] = nil
        if selection == activity.id { selection = activities.last?.id }
    }
}
