import XCTest
@testable import WatchClimber

final class AmagiRouteTests: XCTestCase {
    private func amagiRoute() throws -> PlannedRoute {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "amagi-course", withExtension: "json"))
        return try JSONDecoder().decode(PlannedRoute.self, from: Data(contentsOf: url))
    }

    func testAmagiCanBeSelectedManuallyAndByFreshGPS() throws {
        let selection = try XCTUnwrap(MountainSelection(rawValue: "amagi"))
        XCTAssertEqual(selection.title, "天城山")
        let options = [Terrain.load(named: "hanno"), Terrain.load(named: "goryu"), Terrain.load(named: "amagi")].compactMap { $0 }
        let terrain = try XCTUnwrap(Terrain.load(named: "amagi"))
        let now = Date(timeIntervalSince1970: 100)
        let gps = Fix(date: now, latitude: 34.862864, longitude: 139.001789, altitude: 1406, accuracy: 5)
        XCTAssertEqual(selection.terrain(from: options, fix: nil, now: now)?.name, terrain.name)
        XCTAssertEqual(MountainSelection.automatic.terrain(from: options, fix: gps, now: now)?.name, terrain.name)
        XCTAssertTrue(MountainSelection.automatic.terrain(from: options, fix: gps, now: now.addingTimeInterval(31))?.name.hasPrefix("飯能") == true)
        let poorGPS = Fix(date: now, latitude: gps.latitude, longitude: gps.longitude, altitude: 1406, accuracy: 100)
        XCTAssertTrue(MountainSelection.automatic.terrain(from: options, fix: poorGPS, now: now)?.name.hasPrefix("飯能") == true)
        XCTAssertNotNil(PlannedRoute.load(), "Keep the Goryu route bundled")
    }

    func testAmagiBundlePreservesLoopAndCoversEveryPointWithRealTerrain() throws {
        let route = try amagiRoute()
        let terrain = try XCTUnwrap(Terrain.load(named: "amagi"))
        XCTAssertEqual(route.id, "amagi-shakunage")
        XCTAssertEqual(route.name, "天城山 シャクナゲコース")
        XCTAssertGreaterThan(route.points.count, 340)
        XCTAssertLessThan(route.points.count, 390)
        XCTAssertEqual(route.landmarks.count, 12)
        XCTAssertGreaterThan(route.totalM, 7_900)
        XCTAssertLessThan(route.totalM, 8_300)
        let names = route.landmarks.map(\.name)
        XCTAssertTrue(names[3].contains("万二郎岳"))
        XCTAssertTrue(names[6].contains("万三郎岳"))
        XCTAssertTrue(names[8].contains("涸沢"))
        XCTAssertEqual(route.points.first?.latitude, route.points.last?.latitude)
        XCTAssertEqual(route.points.first?.longitude, route.points.last?.longitude)
        XCTAssertEqual(route.landmarks.map(\.pointIndex), route.landmarks.map(\.pointIndex).sorted())
        for point in route.points {
            XCTAssertNotNil(point.altitude)
            let grid = try XCTUnwrap(terrain.grid(latitude: point.latitude, longitude: point.longitude))
            XCTAssertNotNil(terrain.height(x: grid.x, y: grid.y))
        }
    }

    func testDisplayedTerrainLoadsMatchingBundledRoute() throws {
        let amagi = try XCTUnwrap(Terrain.load(named: "amagi"))
        let goryu = try XCTUnwrap(Terrain.load(named: "goryu"))
        XCTAssertEqual(PlannedRoute.load(for: amagi)?.id, "amagi-shakunage")
        XCTAssertEqual(PlannedRoute.load(for: goryu)?.id, "goryu-tomi-out-and-back")
        XCTAssertNil(PlannedRoute.load(for: nil))
    }

    func testAmagiSharedJunctionRespectsReturnProgressHint() throws {
        let route = try amagiRoute()
        let outward = route.landmarks[2]
        let returning = route.landmarks[9]
        let point = route.points[outward.pointIndex]
        let outbound = route.nearest(to: point.latitude, longitude: point.longitude,
                                     progressHintM: route.landmarkDistance(outward))
        let inbound = route.nearest(to: point.latitude, longitude: point.longitude,
                                    progressHintM: route.landmarkDistance(returning))
        XCTAssertLessThan(outbound.offsetM, 1)
        XCTAssertLessThan(inbound.offsetM, 1)
        XCTAssertLessThan(outbound.distanceM, 1000)
        XCTAssertGreaterThan(inbound.distanceM, 7000)
    }
}
