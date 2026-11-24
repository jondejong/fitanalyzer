import Foundation

/// A user-defined lap: a stretch of the activity between two distances.
struct IntervalLap: Identifiable {
    let id: Int             // 1-based position
    let start: Double       // m from the start of the activity
    let end: Double
    let time: TimeInterval  // moving time
    var maxSpeed: Double?   // m/s
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var minHeartRate: Double?

    var distance: Double { end - start }
    var avgSpeed: Double? { time > 0 ? distance / time : nil }
}

/// The activity's distance/time track, used to cut it into laps at arbitrary distances.
///
/// Laps are described by `splits`: the sorted distances (in metres) at which one
/// lap ends and the next begins. The last lap always runs to the end of the activity.
struct IntervalTrack {
    private let samples: [Sample]   // only those with a distance
    private let distances: [Double]
    let totalDistance: Double

    init(_ activity: Activity) {
        samples = activity.samples.filter { $0.distance != nil }
        distances = samples.map { $0.distance ?? 0 }
        totalDistance = distances.last ?? 0
    }

    /// Index of the first sample at or beyond `distance`.
    private func index(atOrAfter distance: Double) -> Int {
        var low = 0, high = distances.count
        while low < high {
            let mid = (low + high) / 2
            if distances[mid] < distance { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Moving time at which `distance` was reached, interpolated between samples.
    private func time(at distance: Double) -> TimeInterval {
        guard !samples.isEmpty else { return 0 }
        let i = index(atOrAfter: distance)
        if i >= samples.count { return samples[samples.count - 1].moving }
        let d1 = distances[i], t1 = samples[i].moving
        let d0 = i > 0 ? distances[i - 1] : 0
        let t0 = i > 0 ? samples[i - 1].moving : 0
        guard d1 > d0 else { return t1 }
        return t0 + (t1 - t0) * (distance - d0) / (d1 - d0)
    }

    func laps(splits: [Double]) -> [IntervalLap] {
        guard totalDistance > 0 else { return [] }
        let bounds = [0] + splits.filter { $0 > 0 && $0 < totalDistance } + [totalDistance]
        return (0..<bounds.count - 1).map { i in
            let start = bounds[i], end = bounds[i + 1]
            var lap = IntervalLap(id: i + 1, start: start, end: end, time: time(at: end) - time(at: start))
            // Samples with start < distance <= end (the first lap also takes distance 0).
            let from = i == 0 ? 0 : index(atOrAfter: start.nextUp)
            let to = index(atOrAfter: end.nextUp)
            if from < to {
                let slice = samples[from..<to]
                lap.maxSpeed = slice.compactMap(\.speed).max()
                let hr = slice.compactMap(\.heartRate)
                if !hr.isEmpty {
                    lap.avgHeartRate = hr.reduce(0, +) / Double(hr.count)
                    lap.maxHeartRate = hr.max()
                    lap.minHeartRate = hr.min()
                }
            }
            return lap
        }
    }

    // MARK: Editing splits

    /// Laps shorter than this are not worth keeping as a trailing remainder.
    private let minimumLap = 1.0

    private func normalized(_ splits: [Double]) -> [Double] {
        var result: [Double] = []
        for split in splits.sorted() where split >= minimumLap && split <= totalDistance - minimumLap {
            if let last = result.last, split - last < minimumLap { continue }
            result.append(split)
        }
        return result
    }

    /// A split every `step` metres.
    func splits(every step: Double) -> [Double] {
        guard step > 0 else { return [] }
        var result = normalized(Array(stride(from: step, to: totalDistance, by: step)))
        // Fold a sliver at the end (under a tenth of a lap) into the previous lap.
        if let last = result.last, totalDistance - last < step / 10 { result.removeLast() }
        return result
    }

    /// Splits at the ends of the laps recorded in the file.
    func splits(from recorded: [Lap]) -> [Double] {
        var total = 0.0
        return normalized(recorded.compactMap(\.distance).map { total += $0; return total })
    }

    /// Merges laps `first...last` (0-based) into one.
    func combining(_ splits: [Double], laps first: Int, through last: Int) -> [Double] {
        guard first < last, first >= 0, last <= splits.count else { return splits }
        var result = splits
        result.removeSubrange(first..<last)
        return result
    }

    /// Sets the length of lap `index` (0-based). Later laps keep their lengths and
    /// shift along; the final lap absorbs the difference.
    func settingDistance(_ splits: [Double], ofLap index: Int, to distance: Double) -> [Double] {
        guard distance >= minimumLap, index >= 0, index <= splits.count else { return splits }
        let start = index == 0 ? 0 : splits[index - 1]
        var result = splits
        if index == splits.count {
            result.append(start + distance) // shortening the final lap leaves a new remainder
        } else {
            let delta = start + distance - splits[index]
            for i in index..<result.count { result[i] += delta }
        }
        return normalized(result)
    }
}
