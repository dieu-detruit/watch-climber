import XCTest
@testable import WatchClimber

final class RouteDisplayTests: XCTestCase {
    private func route() throws -> PlannedRoute {
        let json = """
        {"id":"fixture","name":"Trail","sourceUrl":"https://example.com/","distanceM":2000,"ascentM":100,"descentM":0,
        "points":[{"latitude":36.65,"longitude":137.78,"altitude":1700},{"latitude":36.66,"longitude":137.78,"altitude":1800}],
        "landmarks":[{"name":"Start","pointIndex":0},{"name":"Summit","pointIndex":1}]}
        """
        return try JSONDecoder().decode(PlannedRoute.self, from: Data(json.utf8))
    }
    private func fix(at second: Double, longitude: Double = 137.78, accuracy: Double = 5) -> Fix {
        Fix(date: Date(timeIntervalSince1970: second), latitude: 36.655, longitude: longitude, altitude: 1750, accuracy: accuracy)
    }
    func testInspectionNeverChangesLiveGPSOrRecording() throws {
        let route = try route()
        let gps = fix(at: 100)
        var inspection = RouteInspection()
        inspection.inspect(route.totalM, totalM: route.totalM)
        let display = RouteDisplayContext(route: route, fix: gps, now: Date(timeIntervalSince1970: 101), progressHintM: 0, inspection: inspection)
        XCTAssertEqual(display.liveFix?.latitude, 36.655)
        XCTAssertEqual(display.position.point.latitude, 36.66)
        XCTAssertEqual(display.liveMatch!.distanceM, route.totalM / 2, accuracy: 1)
        XCTAssertTrue(display.isInspecting)
    }
    func testMissingStaleInvalidAndFarFutureGPSNeverCreateCurrentMarker() throws {
        let route = try route()
        for gps in [nil, fix(at: 60), fix(at: 100, accuracy: 100), fix(at: 150)] {
            let display = RouteDisplayContext(route: route, fix: gps, now: Date(timeIntervalSince1970: 100), progressHintM: 0, inspection: RouteInspection())
            XCTAssertNil(display.liveFix)
            XCTAssertNil(display.liveMatch)
            XCTAssertFalse(display.isInspecting)
            XCTAssertEqual(display.position.distanceM, 0)
        }
    }
    func testOffCourseGPSIsNotProjectedAsCurrentOnProfile() throws {
        let route = try route()
        let display = RouteDisplayContext(route: route, fix: fix(at: 100, longitude: 138), now: Date(timeIntervalSince1970: 101), progressHintM: 0, inspection: RouteInspection())
        XCTAssertNotNil(display.liveFix)
        XCTAssertFalse(display.isOnCourse)
        XCTAssertNil(display.profileCurrentDistanceM)
    }
    func testReturnToGPSRestoresFollowWithoutMutatingFix() throws {
        let route = try route()
        var inspection = RouteInspection()
        inspection.inspect(route.totalM, totalM: route.totalM)
        inspection.followGPS()
        let display = RouteDisplayContext(route: route, fix: fix(at: 100), now: Date(timeIntervalSince1970: 101), progressHintM: 0, inspection: inspection)
        XCTAssertFalse(display.isInspecting)
        XCTAssertEqual(display.position.distanceM, route.totalM / 2, accuracy: 1)
    }
}
