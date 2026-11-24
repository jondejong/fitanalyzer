import Foundation

enum UnitSystem: String, CaseIterable, Identifiable {
    case metric, imperial

    var id: String { rawValue }
    var label: String { self == .metric ? "Metric" : "Imperial" }

    static var systemDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    /// Metres in one distance unit (km or mi).
    var distanceMeters: Double { self == .metric ? 1000 : 1609.344 }
    var distanceUnit: String { self == .metric ? "km" : "mi" }
    /// Metres in one elevation unit (m or ft).
    var elevationMeters: Double { self == .metric ? 1 : 0.3048 }
    var elevationUnit: String { self == .metric ? "m" : "ft" }
    var speedUnit: String { self == .metric ? "km/h" : "mph" }

    /// Converts m/s to km/h or mph.
    func speedValue(_ mps: Double) -> Double { mps * 3600 / distanceMeters }

    func distance(_ m: Double) -> String {
        String(format: "%.2f %@", m / distanceMeters, distanceUnit)
    }

    func elevation(_ m: Double) -> String {
        String(format: "%.0f %@", m / elevationMeters, elevationUnit)
    }

    func speed(_ mps: Double) -> String {
        String(format: "%.1f %@", speedValue(mps), speedUnit)
    }

    /// Pace as minutes:seconds per km or mile.
    func pace(_ mps: Double) -> String {
        guard mps > 0.1 else { return "–" }
        let seconds = Int((distanceMeters / mps).rounded())
        return String(format: "%d:%02d /%@", seconds / 60, seconds % 60, distanceUnit)
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600, m = total % 3600 / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
