import Foundation

struct Fix: Codable {
    let date: Date
    let latitude, longitude: Double
    let altitude: Double?
    let accuracy: Double
    var usable: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 && accuracy.isFinite && accuracy >= 0 && accuracy <= 50
    }
    func distance(to other: Fix) -> Double {
        let a = latitude * .pi / 180, b = other.latitude * .pi / 180
        let dlat = b - a, dlon = (other.longitude - longitude) * .pi / 180
        let h = pow(sin(dlat/2), 2) + cos(a) * cos(b) * pow(sin(dlon/2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}

struct HikeRecord: Codable {
    enum State: String, Codable { case idle, recording, paused, finished }
    struct Point: Codable { let fix: Fix; let breakBefore: Bool }
    var id = UUID()
    var state: State = .idle
    var elapsed: Double = 0
    var distance: Double = 0
    var ascent: Double = 0
    var points: [Point] = []
    private var previous: Fix?
    private var previousDate: Date?
    private var clockDate: Date?
    private var segmentStart: Date?
    private var altitudeAnchor: Double?

    mutating func breakTrack() { previous = nil; altitudeAnchor = nil }
    mutating func pause() { state = .paused; clockDate = nil; previousDate = nil; breakTrack() }
    mutating func resume(at date: Date = Date()) { state = .recording; segmentStart = date; clockDate = date; previousDate = nil; breakTrack() }
    mutating func advanceTime(to date: Date) {
        guard state == .recording else { return }
        if let previous = clockDate {
            let gap = date.timeIntervalSince(previous)
            guard gap >= 0 else { return }
            elapsed += gap
        }
        clockDate = date
    }
    mutating func prepareAfterRestore() {
        if state == .recording { state = .paused }
        previousDate = nil
        clockDate = nil
        breakTrack()
    }
    mutating func ingest(_ fix: Fix) {
        guard state == .recording, fix.date.timeIntervalSince1970.isFinite else { return }
        if let segmentStart, fix.date < segmentStart { return }
        if let date = previousDate {
            let gap = fix.date.timeIntervalSince(date)
            guard gap > 0 else { return }
            if gap > 30 { breakTrack() }
        }
        advanceTime(to: fix.date)
        previousDate = fix.date
        guard fix.usable else { breakTrack(); return }
        if let last = previous {
            let gap = fix.date.timeIntervalSince(last.date)
            let segment = fix.distance(to: last)
            // Reject implausible hiking jumps; don't connect across rejected fixes.
            if gap <= 0 || segment / gap > 8 { breakTrack(); return }
            distance += segment
        }
        if let altitude = fix.altitude, altitude.isFinite {
            if let anchor = altitudeAnchor {
                let delta = altitude - anchor
                if abs(delta) >= 3 { ascent += max(0, delta); altitudeAnchor = altitude }
            } else { altitudeAnchor = altitude }
        } else { altitudeAnchor = nil }
        points.append(Point(fix: fix, breakBefore: previous == nil))
        previous = fix
    }
}
