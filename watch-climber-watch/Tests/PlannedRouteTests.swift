import XCTest
@testable import WatchClimber

final class PlannedRouteTests: XCTestCase {
    private let northbound = """
    {"id":"fixture","name":"Test route","distanceM":999999,
     "points":[
       {"latitude":36.65,"longitude":137.78,"altitude":1700},
       {"latitude":36.655,"longitude":137.78,"altitude":1800},
       {"latitude":36.66,"longitude":137.78,"altitude":1750}],
     "landmarks":[
       {"name":"Start","pointIndex":0},
       {"name":"Peak","pointIndex":1},
       {"name":"End","pointIndex":2}]}
    """

    private func decode(_ json: String) throws -> PlannedRoute {
        try JSONDecoder().decode(PlannedRoute.self, from: Data(json.utf8))
    }

    private func modified(_ update: (inout [String: Any]) -> Void) throws -> PlannedRoute {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(northbound.utf8)) as? [String: Any])
        update(&object)
        return try JSONDecoder().decode(PlannedRoute.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testBundledCoursePreservesAllPointsAndRepeatedVisits() throws {
        let route = try XCTUnwrap(PlannedRoute.load())
        XCTAssertEqual(route.id, "goryu-tomi-out-and-back")
        XCTAssertEqual(route.name, "五竜岳 · 遠見尾根往復")
        XCTAssertEqual(route.points.count, 790)
        XCTAssertEqual(route.landmarks.count, 19)
        XCTAssertEqual(route.distances.count, route.points.count)
        XCTAssertEqual(route.totalM, 15_256.2483, accuracy: 0.01)
        XCTAssertEqual(route.landmarks.first?.pointIndex, 0)
        XCTAssertEqual(route.landmarks.last?.pointIndex, 789)
        XCTAssertEqual(route.landmarks.first?.name, route.landmarks.last?.name)
        XCTAssertNil(route.landmarks.first?.day)
        XCTAssertNil(route.landmarks.last?.day)
        XCTAssertEqual(route.landmarks.first?.shortName, "アルプス平駅")
        XCTAssertEqual(route.landmarks.filter { $0.name == "五竜山荘テント場" }.count, 2)
        XCTAssertTrue(route.distances.allSatisfy { $0.isFinite })
        for index in 1..<route.distances.count {
            XCTAssertGreaterThanOrEqual(route.distances[index], route.distances[index - 1])
        }
        XCTAssertEqual(route.landmarkDistance(try XCTUnwrap(route.landmarks.last)), route.totalM)
    }

    func testBundledCourseMatchesTheReturnVisitUsingProgressHint() throws {
        let route = try XCTUnwrap(PlannedRoute.load())
        let outward = route.landmarks[8]
        let returning = route.landmarks[10]
        XCTAssertEqual(outward.name, returning.name)
        let point = route.points[returning.pointIndex]
        let match = route.nearest(to: point.latitude, longitude: point.longitude,
                                  progressHintM: route.landmarkDistance(returning))
        XCTAssertEqual(match.distanceM, route.landmarkDistance(returning), accuracy: 0.01)
        XCTAssertEqual(match.offsetM, 0, accuracy: 0.01)
        XCTAssertGreaterThan(match.distanceM, route.landmarkDistance(outward))
    }

    func testDistancesUseGeometryAndInterpolateWithoutChangingTheRoute() throws {
        let route = try decode(northbound)
        XCTAssertEqual(route.totalM, 1111.9493, accuracy: 0.01)
        let result = route.position(at: route.totalM / 4)
        XCTAssertEqual(result.point.latitude, 36.6525, accuracy: 1e-8)
        XCTAssertEqual(result.point.longitude, 137.78, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(result.point.altitude), 1750, accuracy: 1e-6)
        XCTAssertEqual(result.distanceM, route.totalM / 4, accuracy: 1e-6)
        XCTAssertEqual(route.points[0].latitude, 36.65)
    }

    func testPositionClampsEndpointsAndNonfiniteDistances() throws {
        let route = try decode(northbound)
        for invalid in [-100.0, .nan, .infinity, -.infinity] {
            let position = route.position(at: invalid)
            XCTAssertEqual(position.distanceM, 0)
            XCTAssertEqual(position.point, route.points[0])
        }
        let finish = route.position(at: route.totalM + 100)
        XCTAssertEqual(finish.distanceM, route.totalM)
        XCTAssertEqual(finish.point, route.points.last)
    }

    func testMissingAltitudeStaysUnknownBetweenVertices() throws {
        let route = try modified { object in
            var points = object["points"] as! [[String: Any]]
            points[1]["altitude"] = NSNull()
            points[2].removeValue(forKey: "altitude")
            object["points"] = points
        }
        XCTAssertNil(route.points[1].altitude)
        XCTAssertNil(route.points[2].altitude)
        XCTAssertNil(route.position(at: route.totalM / 4).point.altitude)
        XCTAssertNil(route.position(at: route.totalM * 0.75).point.altitude)
        XCTAssertEqual(route.position(at: 0).point.altitude, 1700)
    }

    func testAdjacentDuplicatesDoNotDivideByZeroOrLoseTheFinish() throws {
        let route = try modified { object in
            let points = object["points"] as! [[String: Any]]
            object["points"] = [points[0], points[0], points[1], points[1], points[2], points[2]]
            object["landmarks"] = [["name": "End", "pointIndex": 5]] as [[String: Any]]
        }
        XCTAssertEqual(route.distances[0], route.distances[1])
        XCTAssertEqual(route.distances[2], route.distances[3])
        XCTAssertEqual(route.distances[4], route.distances[5])
        for distance in [0, route.totalM / 2, route.totalM] {
            let position = route.position(at: distance)
            XCTAssertTrue(position.point.latitude.isFinite)
            XCTAssertTrue(position.point.longitude.isFinite)
            XCTAssertEqual(position.distanceM, distance)
        }
        XCTAssertEqual(route.position(at: route.totalM).point, route.points.last)
        let match = route.nearest(to: 36.655, longitude: 137.78)
        XCTAssertEqual(match.distanceM, route.totalM / 2, accuracy: 0.01)
        XCTAssertEqual(match.offsetM, 0, accuracy: 0.01)
    }

    func testNearestProjectsOntoSegmentsRatherThanOnlyVertices() throws {
        let route = try decode(northbound)
        let result = route.nearest(to: 36.654, longitude: 137.78)
        XCTAssertEqual(result.distanceM, route.totalM * 0.4, accuracy: 0.01)
        XCTAssertEqual(result.offsetM, 0, accuracy: 0.01)
        XCTAssertGreaterThan(route.nearest(to: 36.654, longitude: 137.80).offsetM, 1700)
    }

    func testProgressHintDistinguishesTheReturnLegAndRepeatedFinish() throws {
        let route = try modified { object in
            let points = object["points"] as! [[String: Any]]
            object["points"] = points + [points[1], points[0]]
        }
        let outbound = route.nearest(to: 36.655, longitude: 137.78)
        let inbound = route.nearest(to: 36.655, longitude: 137.78, progressHintM: route.totalM * 0.75)
        XCTAssertEqual(outbound.distanceM, route.totalM * 0.25, accuracy: 0.01)
        XCTAssertEqual(inbound.distanceM, route.totalM * 0.75, accuracy: 0.01)
        XCTAssertEqual(route.nearest(to: 36.65, longitude: 137.78, progressHintM: route.totalM).distanceM,
                       route.totalM, accuracy: 0.01)
        XCTAssertEqual(route.nearest(to: 36.655, longitude: 137.78, progressHintM: .nan).distanceM,
                       outbound.distanceM, accuracy: 0.01)
    }

    func testInvalidGPSCannotProduceAnApparentlyValidMatch() throws {
        let route = try decode(northbound)
        for coordinates in [(Double.nan, 137.78), (91, 137.78), (36.65, Double.infinity), (36.65, 181)] {
            let match = route.nearest(to: coordinates.0, longitude: coordinates.1)
            XCTAssertEqual(match.offsetM, .infinity)
            XCTAssertEqual(match.distanceM, 0)
        }
    }

    func testLandmarksAdvanceInRouteOrderAndKeepSuppliedPosition() throws {
        let route = try modified { object in
            let landmarks: [[String: Any]] = [
                ["name": "Start", "pointIndex": 0],
                ["name": "Peak", "pointIndex": 1, "day": 2,
                 "position": ["latitude": 36.656, "longitude": 137.781, "altitude": 1900]],
                ["name": "End", "pointIndex": 2]
            ]
            object["landmarks"] = landmarks
        }
        let peak = try XCTUnwrap(route.nextLandmark(after: 0))
        XCTAssertEqual(peak.name, "Peak")
        XCTAssertEqual(route.landmarkDistance(peak), route.totalM / 2, accuracy: 0.01)
        XCTAssertEqual(route.landmarkPosition(peak).latitude, 36.656)
        XCTAssertEqual(route.landmarkPosition(peak).altitude, 1900)
        XCTAssertEqual(route.landmarkPosition(route.landmarks[0]), route.points[0])
        XCTAssertEqual(route.nextLandmark(after: route.landmarkDistance(peak))?.name, "End")
        XCTAssertNil(route.nextLandmark(after: route.totalM))
    }

    func testRejectsTooFewPointsAndZeroLengthGeometry() throws {
        for count in [0, 1, 2] {
            XCTAssertThrowsError(try modified { object in
                let point = (object["points"] as! [[String: Any]])[0]
                object["points"] = Array(repeating: point, count: count)
                object["landmarks"] = []
            })
        }
    }

    func testRejectsInvalidCoordinatesAndAltitudeTypes() throws {
        for (key, value) in [("latitude", 90.1), ("latitude", -90.1), ("longitude", 180.1), ("longitude", -180.1)] {
            XCTAssertThrowsError(try modified { object in
                var points = object["points"] as! [[String: Any]]
                points[0][key] = value
                object["points"] = points
            })
        }
        XCTAssertThrowsError(try modified { object in
            var points = object["points"] as! [[String: Any]]
            points[0]["altitude"] = "unknown"
            object["points"] = points
        })
    }

    func testRejectsInvalidLandmarkIndicesAndPositions() throws {
        for index in [-1.0, 3.0, 1.5] {
            XCTAssertThrowsError(try modified { object in
                object["landmarks"] = [["name": "Invalid", "pointIndex": index]] as [[String: Any]]
            })
        }
        XCTAssertThrowsError(try modified { object in
            object["landmarks"] = [["name": "Invalid", "pointIndex": 1,
                                    "position": ["latitude": 95, "longitude": 137.78]]] as [[String: Any]]
        })
    }

    func testRejectsNonfiniteValuesEvenWithPermissiveJSONDecoder() {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for (source, replacement) in [("36.65,", "\"NaN\","), ("137.78,", "\"Infinity\","),
                                      ("1700}", "\"-Infinity\"}")] {
            let json = northbound.replacingOccurrences(of: source, with: replacement)
            XCTAssertThrowsError(try decoder.decode(PlannedRoute.self, from: Data(json.utf8)))
        }
    }

    func testInspectionStartsAtLiveProgressAndRemainsIndependentUntilFollowGPS() throws {
        let route = try decode(northbound)
        var inspection = RouteInspection()
        XCTAssertNil(inspection.distanceM)
        inspection.scrub(steps: 1, liveDistanceM: 400, totalM: route.totalM)
        XCTAssertEqual(inspection.distanceM, 450)
        inspection.scrub(steps: -0.5, liveDistanceM: 800, totalM: route.totalM)
        XCTAssertEqual(inspection.distanceM, 425)
        XCTAssertEqual(route.nearest(to: 36.654, longitude: 137.78).distanceM, route.totalM * 0.4, accuracy: 0.01)
        XCTAssertEqual(inspection.distanceM, 425)
        inspection.followGPS()
        XCTAssertNil(inspection.distanceM)
        inspection.scrub(steps: 1, liveDistanceM: nil, totalM: route.totalM)
        XCTAssertEqual(inspection.distanceM, 50)
    }

    func testInspectionClampsAndIgnoresInvalidCrownSteps() {
        var inspection = RouteInspection()
        inspection.scrub(steps: 0, liveDistanceM: 100, totalM: 1000)
        XCTAssertNil(inspection.distanceM)
        inspection.scrub(steps: .nan, liveDistanceM: 100, totalM: 1000)
        XCTAssertNil(inspection.distanceM)
        inspection.inspect(900, totalM: 1000)
        inspection.scrub(steps: 20, liveDistanceM: nil, totalM: 1000)
        XCTAssertEqual(inspection.distanceM, 1000)
        inspection.scrub(steps: -100, liveDistanceM: nil, totalM: 1000)
        XCTAssertEqual(inspection.distanceM, 0)
        inspection.inspect(400, totalM: 1000)
        inspection.scrub(steps: .infinity, liveDistanceM: nil, totalM: 1000)
        XCTAssertEqual(inspection.distanceM, 400)
        inspection.inspect(.nan, totalM: 1000)
        XCTAssertEqual(inspection.distanceM, 0)
        inspection.inspect(10, totalM: .nan)
        XCTAssertEqual(inspection.distanceM, 0)
        inspection.inspect(-1, totalM: 1000)
        XCTAssertEqual(inspection.distanceM, 0)
    }
}
