import XCTest
@testable import WatchClimber

final class ClimberTests: XCTestCase {
    func testActualDEMPixelCoordinates() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "goryu", withExtension: "json"))
        let terrain = try JSONDecoder().decode(Terrain.self, from: Data(contentsOf: url))
        let world: Double = 256 * pow(2, 14)
        for (col, row) in [(0.0, 0.0), (Double(terrain.columns-1), Double(terrain.rows-1)), (100, 80), (111.25, 79.75)] {
            let lon = (14459 * 256 + col * 2 + 0.5) / world * 360 - 180
            let lat = atan(sinh(.pi * (1 - 2 * (6394 * 256 + row * 2 + 0.5) / world))) * 180 / .pi
            let point = try XCTUnwrap(terrain.grid(latitude: lat, longitude: lon))
            XCTAssertEqual(point.x, col, accuracy: 1e-7)
            XCTAssertEqual(point.y, row, accuracy: 1e-7)
        }
        XCTAssertNil(terrain.grid(latitude: 35, longitude: 139))
        XCTAssertNil(terrain.grid(latitude: .nan, longitude: 137.7))
    }

    func testTerrainDetailZoomsIntoSourceResolutionWithBoundedMesh() {
        XCTAssertEqual(TerrainDetail(spacing: 15, zoom: 12).step, 1)
        XCTAssertEqual(TerrainDetail(spacing: 15, zoom: 1).radius * 15, 3660, accuracy: 0.001)
        for zoom in [0.7, 1, 2, 4, 8, 12] {
            let detail = TerrainDetail(spacing: 15, zoom: zoom)
            // Grid alignment adds at most one extra cell per axis.
            let cells = ceil(2 * detail.radius / Double(detail.step)) + 1
            XCTAssertLessThanOrEqual(2 * cells * cells, 13200)
        }
    }

    private func fix(_ second: Double, _ lon: Double = 137.75, altitude: Double? = 2000, accuracy: Double = 5) -> Fix {
        Fix(date: Date(timeIntervalSince1970: second), latitude: 36.65, longitude: lon, altitude: altitude, accuracy: accuracy)
    }

    func testPauseAndGPSGapsDoNotBridgeTrack() {
        var record = HikeRecord()
        record.state = .recording
        record.ingest(fix(100))
        record.ingest(fix(110, 137.7501, altitude: 2005))
        XCTAssertGreaterThan(record.distance, 0)
        XCTAssertEqual(record.ascent, 5)
        let distance = record.distance
        record.ingest(fix(120, 137.76, accuracy: 200))
        record.ingest(fix(130, 137.77))
        XCTAssertEqual(record.distance, distance)
        XCTAssertTrue(record.points.last!.breakBefore)
        record.pause()
        record.resume(at: Date(timeIntervalSince1970: 300))
        record.ingest(fix(300, 137.78))
        XCTAssertEqual(record.distance, distance)
        XCTAssertEqual(record.elapsed, 30)
    }

    func testStaleAndMissingAltitude() {
        var record = HikeRecord()
        record.state = .recording
        record.ingest(fix(100))
        record.ingest(fix(99, 138))
        record.ingest(fix(110, altitude: nil))
        record.ingest(fix(120, altitude: 2200))
        XCTAssertEqual(record.points.count, 3)
        XCTAssertEqual(record.ascent, 0)
    }

    func testElapsedTimeAdvancesWhileGPSIsStationary() {
        var record = HikeRecord()
        record.resume(at: Date(timeIntervalSince1970: 100))
        record.advanceTime(to: Date(timeIntervalSince1970: 130))
        record.advanceTime(to: Date(timeIntervalSince1970: 140))
        XCTAssertEqual(record.elapsed, 40)
        record.pause()
        record.advanceTime(to: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(record.elapsed, 40)
    }

    func testResumeRejectsBufferedLocationsFromPause() {
        var record = HikeRecord()
        record.resume(at: Date(timeIntervalSince1970: 100))
        record.ingest(fix(100))
        record.pause()
        record.resume(at: Date(timeIntervalSince1970: 200))
        record.ingest(fix(190, 138))
        XCTAssertEqual(record.points.count, 1)
        record.ingest(fix(201, 137.8))
        XCTAssertTrue(record.points.last!.breakBefore)
        XCTAssertEqual(record.distance, 0)
    }

    func testRestoredRecordingIsPaused() throws {
        var record = HikeRecord()
        record.state = .recording
        record.ingest(fix(100))
        var restored = try JSONDecoder().decode(HikeRecord.self, from: JSONEncoder().encode(record))
        restored.prepareAfterRestore()
        XCTAssertEqual(restored.state, .paused)
        restored.resume(at: Date(timeIntervalSince1970: 1000))
        restored.ingest(fix(1000, 138))
        XCTAssertEqual(restored.elapsed, 0)
        XCTAssertEqual(restored.distance, 0)
    }
}
