import Foundation
import CoreLocation

/// One point of the recorded track (a FIT `record` message), in SI units.
struct Sample: Identifiable, Sendable {
    let id: Int
    let time: Date
    let elapsed: TimeInterval
    /// Elapsed time with pauses (timer stopped) removed.
    var moving: TimeInterval = 0
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?   // m
    var heartRate: Double?  // bpm
    var cadence: Double?    // rpm, or steps/min for foot sports
    var distance: Double?   // m
    var speed: Double?      // m/s
    var power: Double?      // W

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Lap: Identifiable, Sendable {
    let id: Int
    var time: TimeInterval?  // moving time
    var distance: Double?
    var avgSpeed: Double?
    var avgHeartRate: Double?
    var avgPower: Double?
    var ascent: Double?
}

struct Activity: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let sport: Sport
    /// Variant of the sport, e.g. "Treadmill" or "Virtual"; nil when unremarkable.
    let subSport: String?
    let startTime: Date?
    let samples: [Sample]
    let laps: [Lap]

    var distance: Double?
    var elapsedTime: TimeInterval?
    var movingTime: TimeInterval?
    var calories: Double?
    var ascent: Double?
    var descent: Double?
    var avgSpeed: Double?
    var maxSpeed: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var avgPower: Double?
    var maxPower: Double?
    var avgCadence: Double?
    var maxCadence: Double?

    /// Sport with its variant, e.g. "Running · Treadmill".
    var title: String { subSport.map { "\(sport.name) · \($0)" } ?? sport.name }

    var hasRoute: Bool { samples.contains { $0.latitude != nil } }

    static func load(from url: URL) throws -> Activity {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let messages = try FitDecoder.decode(data)
        return try Activity(messages: messages, name: url.deletingPathExtension().lastPathComponent)
    }

    init(messages: [FitMessage], name: String) throws {
        // FIT global message numbers
        let sessions = messages.filter { $0.globalNumber == 18 }
        let lapMessages = messages.filter { $0.globalNumber == 19 }
        let sportMessage = messages.first { $0.globalNumber == 12 }

        let sportCode = sessions.first?.number(5) ?? sportMessage?.number(0)
        let sport = Sport(code: sportCode.map { Int($0) })
        // Foot sports record cadence per leg; double it to get steps per minute.
        let cadenceScale: Double = sport.isFootSport ? 2 : 1

        let fitEpoch: TimeInterval = 631_065_600 // 1989-12-31T00:00:00Z
        let semicircle = 180.0 / 2_147_483_648.0

        var samples: [Sample] = []
        var firstTime: Date?
        var pausedTotal: TimeInterval = 0
        var stoppedAt: Double?
        for m in messages where m.globalNumber == 20 || m.globalNumber == 21 {
            guard let ts = m.number(253) else { continue }
            if m.globalNumber == 21 {
                // Timer events: each stop/start pair is a pause.
                guard m.number(0) == 0, let type = m.number(1) else { continue }
                if type == 0 {
                    if let stop = stoppedAt, firstTime != nil { pausedTotal += max(0, ts - stop) }
                    stoppedAt = nil
                } else if [1, 4, 8, 9].contains(type), stoppedAt == nil {
                    stoppedAt = ts
                }
                continue
            }
            let time = Date(timeIntervalSince1970: ts + fitEpoch)
            if firstTime == nil { firstTime = time }
            var s = Sample(id: samples.count, time: time, elapsed: time.timeIntervalSince(firstTime ?? time))
            if let lat = m.number(0), let lon = m.number(1) {
                s.latitude = lat * semicircle
                s.longitude = lon * semicircle
            }
            s.altitude = (m.number(78) ?? m.number(2)).map { $0 / 5 - 500 }
            s.heartRate = m.number(3)
            s.cadence = m.number(4).map { $0 * cadenceScale }
            s.distance = m.number(5).map { $0 / 100 }
            s.speed = (m.number(73) ?? m.number(6)).map { $0 / 1000 }
            s.power = m.number(7)
            let pausedNow = stoppedAt.map { max(0, ts - $0) } ?? 0
            s.moving = max(samples.last?.moving ?? 0, s.elapsed - pausedTotal - pausedNow)
            samples.append(s)
        }

        guard !samples.isEmpty || !sessions.isEmpty else { throw FitError.noData }

        func total(_ field: UInt8, scale: Double = 1) -> Double? {
            let values = sessions.compactMap { $0.number(field) }
            return values.isEmpty ? nil : values.reduce(0, +) / scale
        }
        func mean(_ key: (Sample) -> Double?) -> Double? {
            let values = samples.compactMap(key)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        func peak(_ key: (Sample) -> Double?) -> Double? { samples.compactMap(key).max() }
        let single = sessions.count == 1 ? sessions.first : nil
        // Some apps (e.g. Zwift) write 0 rather than "invalid" for things they don't measure.
        func nonZero(_ value: Double?) -> Double? { value == 0 ? nil : value }

        self.name = name
        self.sport = sport
        self.subSport = sessions.first?.number(6).flatMap { Sport.subSportName(Int($0)) }
        self.samples = samples
        self.startTime = sessions.first?.number(2).map { Date(timeIntervalSince1970: $0 + fitEpoch) } ?? samples.first?.time

        distance = total(9, scale: 100) ?? samples.last(where: { $0.distance != nil })?.distance
        elapsedTime = total(7, scale: 1000) ?? samples.last?.elapsed
        movingTime = total(8, scale: 1000) ?? elapsedTime
        calories = nonZero(total(11))
        ascent = nonZero(total(22))
        descent = nonZero(total(23))
        if let distance, let movingTime, distance > 0, movingTime > 0 {
            avgSpeed = distance / movingTime
        }
        maxSpeed = peak(\.speed) ?? (single?.number(125) ?? single?.number(15)).map { $0 / 1000 }
        avgHeartRate = single?.number(16) ?? mean(\.heartRate)
        maxHeartRate = single?.number(17) ?? peak(\.heartRate)
        avgPower = nonZero(single?.number(20) ?? mean(\.power))
        maxPower = nonZero(single?.number(21) ?? peak(\.power))
        avgCadence = single?.number(18).map { $0 * cadenceScale } ?? mean(\.cadence)
        maxCadence = single?.number(19).map { $0 * cadenceScale } ?? peak(\.cadence)

        laps = lapMessages.enumerated().map { index, m in
            var lap = Lap(id: index + 1)
            // Timer time excludes pauses, so it agrees with the lap's pace.
            lap.time = (m.number(8) ?? m.number(7)).map { $0 / 1000 }
            lap.distance = m.number(9).map { $0 / 100 }
            if let d = lap.distance, let t = lap.time, d > 0, t > 0 {
                lap.avgSpeed = d / t
            }
            lap.avgHeartRate = m.number(15)
            lap.avgPower = nonZero(m.number(19))
            lap.ascent = nonZero(m.number(21))
            return lap
        }
    }
}

enum Sport: Sendable {
    case running, cycling, swimming, walking, hiking, other(String)

    init(code: Int?) {
        switch code {
        case 1: self = .running
        case 2: self = .cycling
        case 5: self = .swimming
        case 11: self = .walking
        case 17: self = .hiking
        case 4: self = .other("Fitness Equipment")
        case 10: self = .other("Training")
        case 12: self = .other("Cross-Country Skiing")
        case 13: self = .other("Alpine Skiing")
        case 14: self = .other("Snowboarding")
        case 15: self = .other("Rowing")
        case 19: self = .other("Paddling")
        default: self = .other("Activity")
        }
    }

    static func subSportName(_ code: Int) -> String? {
        switch code {
        case 1: return "Treadmill"
        case 3: return "Trail"
        case 4: return "Track"
        case 6: return "Indoor"
        case 8: return "Mountain"
        case 17: return "Lap Swimming"
        case 18: return "Open Water"
        case 45: return "Indoor"
        case 58: return "Virtual"
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .other(let name): return name
        }
    }

    var symbol: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .other: return "figure.mixed.cardio"
        }
    }

    var isFootSport: Bool {
        switch self {
        case .running, .walking, .hiking: return true
        default: return false
        }
    }
}
