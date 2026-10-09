import Foundation

struct RoutePoint: Decodable, Equatable {
    let latitude, longitude: Double
    let altitude: Double?

    fileprivate var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
            && (altitude?.isFinite ?? true)
    }
}

struct RouteLandmark: Decodable, Equatable {
    let name: String
    let pointIndex: Int
    let day: Int?
    let position: RoutePoint?

    var shortName: String {
        name.replacingOccurrences(of: "五竜テレキャビン ", with: "")
    }
}

struct RoutePosition {
    let point: RoutePoint
    let distanceM: Double
}

struct RouteMatch {
    let distanceM: Double
    let offsetM: Double
}

/// Immutable planned geometry. These distances never change the recorded hike.
struct PlannedRoute: Decodable {
    let id, name: String
    let points: [RoutePoint]
    let landmarks: [RouteLandmark]
    let distances: [Double]
    let totalM: Double

    private static let earthRadius = 6_371_000.0
    private static let radians = Double.pi / 180

    private enum CodingKeys: String, CodingKey {
        case id, name, points, landmarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let decodedPoints = try container.decode([RoutePoint].self, forKey: .points)
        guard decodedPoints.count >= 2, decodedPoints.allSatisfy({ $0.isValid }) else {
            throw DecodingError.dataCorruptedError(forKey: .points, in: container,
                                                   debugDescription: "A route needs at least two valid coordinates.")
        }
        let decodedLandmarks = try container.decode([RouteLandmark].self, forKey: .landmarks)
        guard decodedLandmarks.allSatisfy({ landmark in
            decodedPoints.indices.contains(landmark.pointIndex) && (landmark.position?.isValid ?? true)
        }) else {
            throw DecodingError.dataCorruptedError(forKey: .landmarks, in: container,
                                                   debugDescription: "Landmarks must reference route points and valid positions.")
        }
        var cumulative = [0.0]
        cumulative.reserveCapacity(decodedPoints.count)
        for index in 1..<decodedPoints.count {
            cumulative.append(cumulative[index - 1] + Self.distance(decodedPoints[index - 1], decodedPoints[index]))
        }
        guard let total = cumulative.last, total.isFinite, total > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .points, in: container,
                                                   debugDescription: "A route must have a positive finite length.")
        }
        points = decodedPoints
        landmarks = decodedLandmarks
        distances = cumulative
        totalM = total
    }

    static func load() -> PlannedRoute? {
        guard let url = Bundle.main.url(forResource: "goryu-course", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PlannedRoute.self, from: data)
    }

    private static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let latitudeA = a.latitude * radians, latitudeB = b.latitude * radians
        let dLatitude = (b.latitude - a.latitude) * radians
        let dLongitude = (b.longitude - a.longitude) * radians
        let haversine = pow(sin(dLatitude / 2), 2)
            + cos(latitudeA) * cos(latitudeB) * pow(sin(dLongitude / 2), 2)
        return earthRadius * 2 * asin(sqrt(min(1, max(0, haversine))))
    }

    func position(at requestedM: Double) -> RoutePosition {
        let distanceM = Self.clamp(requestedM, totalM: totalM)
        if distanceM <= 0 { return RoutePosition(point: points[0], distanceM: 0) }
        if distanceM >= totalM { return RoutePosition(point: points[points.count - 1], distanceM: totalM) }

        // First vertex at or beyond the cursor. Repeated coordinates are valid.
        var lower = 1, upper = distances.count - 1
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if distances[middle] < distanceM { lower = middle + 1 } else { upper = middle }
        }
        let a = points[lower - 1], b = points[lower]
        let span = distances[lower] - distances[lower - 1]
        let fraction = span > 0 ? (distanceM - distances[lower - 1]) / span : 0
        if fraction >= 1 { return RoutePosition(point: b, distanceM: distanceM) }
        let altitude: Double?
        if let altitudeA = a.altitude, let altitudeB = b.altitude {
            altitude = altitudeA + (altitudeB - altitudeA) * fraction
        } else {
            altitude = nil
        }
        let point = RoutePoint(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                               longitude: a.longitude + (b.longitude - a.longitude) * fraction,
                               altitude: altitude)
        return RoutePosition(point: point, distanceM: distanceM)
    }

    /// Projects GPS onto each segment; the hint only breaks near-equal spatial matches.
    /// A hint cannot establish the correct leg after an ambiguous cold start.
    func nearest(to latitude: Double, longitude: Double, progressHintM: Double = 0) -> RouteMatch {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else {
            return RouteMatch(distanceM: 0, offsetM: .infinity)
        }
        let hint = Self.clamp(progressHintM, totalM: totalM)
        let longitudeScale = cos(latitude * Self.radians) * Self.radians * Self.earthRadius
        let latitudeScale = Self.radians * Self.earthRadius
        var result = RouteMatch(distanceM: 0, offsetM: .infinity)
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            let ax = (a.longitude - longitude) * longitudeScale
            let ay = (a.latitude - latitude) * latitudeScale
            let bx = (b.longitude - longitude) * longitudeScale
            let by = (b.latitude - latitude) * latitudeScale
            let dx = bx - ax, dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let fraction = lengthSquared > 0 ? max(0, min(1, -(ax * dx + ay * dy) / lengthSquared)) : 0
            let offsetM = hypot(ax + fraction * dx, ay + fraction * dy)
            let distanceM = distances[index - 1] + fraction * (distances[index] - distances[index - 1])
            if offsetM < result.offsetM - 0.5
                || (abs(offsetM - result.offsetM) <= 0.5 && abs(distanceM - hint) < abs(result.distanceM - hint)) {
                result = RouteMatch(distanceM: distanceM, offsetM: offsetM)
            }
        }
        return result
    }

    func nextLandmark(after distanceM: Double) -> RouteLandmark? {
        let cursor = Self.clamp(distanceM, totalM: totalM)
        return landmarks.filter { landmarkDistance($0) > cursor }
            .min { landmarkDistance($0) < landmarkDistance($1) }
    }

    func landmarkDistance(_ landmark: RouteLandmark) -> Double {
        distances[landmark.pointIndex]
    }

    func landmarkPosition(_ landmark: RouteLandmark) -> RoutePoint {
        landmark.position ?? points[landmark.pointIndex]
    }

    fileprivate static func clamp(_ distanceM: Double, totalM: Double) -> Double {
        let total = totalM.isFinite ? max(0, totalM) : 0
        return max(0, min(total, distanceM.isFinite ? distanceM : 0))
    }
}

/// An inspection cursor is separate from live GPS progress and recorded distance.
struct RouteInspection {
    var distanceM: Double? = nil

    mutating func inspect(_ distance: Double, totalM: Double) {
        distanceM = PlannedRoute.clamp(distance, totalM: totalM)
    }

    mutating func scrub(steps: Double, liveDistanceM: Double?, totalM: Double) {
        guard steps.isFinite, steps != 0 else { return }
        let total = totalM.isFinite ? max(0, totalM) : 0
        let start = PlannedRoute.clamp(distanceM ?? liveDistanceM ?? 0, totalM: total)
        // Keep huge finite Crown deltas bounded even if multiplication overflows.
        distanceM = max(0, min(total, start + steps * 50))
    }

    mutating func followGPS() { distanceM = nil }
}
