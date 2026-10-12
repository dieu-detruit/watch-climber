import XCTest
@testable import WatchClimber

final class RecordExportTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSnapshotsPreserveOldMalformedAndUnknownBytesWithoutChangingOriginals() throws {
        let root = try directory()
        let fixtures = ["current-hike.json": Data("{broken\n\u{0000}".utf8),
                        "hike-old.json": Data(" { \"futureSchema\": 99, \"points\": [] }\r\n".utf8)]
        for (name, bytes) in fixtures { try bytes.write(to: root.appendingPathComponent(name)) }
        let store = RecordExportStore(directory: root.appendingPathComponent("RecordExports"))
        let files = try store.snapshotRecords(in: root)
        XCTAssertEqual(files.count, 2)
        for file in files {
            XCTAssertEqual(try Data(contentsOf: file.url), fixtures[file.originalName])
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(file.originalName)), fixtures[file.originalName])
        }
    }

    func testRetryDeduplicatesButChangedCurrentKeepsBothVersions() throws {
        let root = try directory()
        let source = root.appendingPathComponent("current-hike.json")
        try Data("old".utf8).write(to: source)
        let store = RecordExportStore(directory: root.appendingPathComponent("RecordExports"))
        let first = try store.snapshotRecords(in: root)
        XCTAssertEqual(try store.snapshotRecords(in: root).map(\.id), first.map(\.id))
        try Data("new".utf8).write(to: source)
        let both = try store.snapshotRecords(in: root)
        XCTAssertEqual(both.count, 2)
        XCTAssertEqual(try Data(contentsOf: first[0].url), Data("old".utf8))
    }

    func testReceiverCopiesTemporaryFileAndDeduplicatesRetry() throws {
        let root = try directory()
        let bytes = Data(" { malformed old record\r\n".utf8)
        let temporary = root.appendingPathComponent("temporary")
        try bytes.write(to: temporary)
        let store = RecordExportStore(directory: root.appendingPathComponent("Received"))
        let metadata = RecordExportFile.metadata(originalName: "hike-old.json", data: bytes)
        let received = try store.receive(temporaryURL: temporary, metadata: metadata)
        let retried = try store.receive(temporaryURL: temporary, metadata: metadata)
        XCTAssertEqual(received.url, retried.url)
        try FileManager.default.removeItem(at: temporary)
        XCTAssertEqual(try Data(contentsOf: received.url), bytes)
        XCTAssertEqual(try store.files().count, 1)
    }

    func testReceiverRejectsCorruptionSizeMismatchAndUnsafeNames() throws {
        let root = try directory()
        let bytes = Data("raw".utf8)
        let temporary = root.appendingPathComponent("temporary")
        try bytes.write(to: temporary)
        let store = RecordExportStore(directory: root.appendingPathComponent("Received"))
        let valid = RecordExportFile.metadata(originalName: "current-hike.json", data: bytes)
        for (key, value) in [("originalName", "../current-hike.json" as Any),
                             ("sha256", String(repeating: "0", count: 64) as Any),
                             ("byteCount", 999 as Any), ("version", 2 as Any)] {
            var invalid = valid
            invalid[key] = value
            XCTAssertThrowsError(try store.receive(temporaryURL: temporary, metadata: invalid))
        }
        XCTAssertEqual(try store.files().count, 0)
    }

    func testSnapshotIgnoresUnrelatedFilesAndRejectsSymlink() throws {
        let root = try directory()
        try Data("private".utf8).write(to: root.appendingPathComponent("unrelated.json"))
        let store = RecordExportStore(directory: root.appendingPathComponent("RecordExports"))
        XCTAssertTrue(try store.snapshotRecords(in: root).isEmpty)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("hike-link.json"),
                                                  withDestinationURL: root.appendingPathComponent("unrelated.json"))
        XCTAssertThrowsError(try store.snapshotRecords(in: root))
    }

    func testCorruptedExistingSnapshotIsNeverOverwritten() throws {
        let root = try directory()
        let bytes = Data("original".utf8)
        try bytes.write(to: root.appendingPathComponent("current-hike.json"))
        let store = RecordExportStore(directory: root.appendingPathComponent("RecordExports"))
        let file = try XCTUnwrap(store.snapshotRecords(in: root).first)
        try Data("corrupt".utf8).write(to: file.url)
        XCTAssertThrowsError(try store.snapshotRecords(in: root))
        XCTAssertEqual(try Data(contentsOf: file.url), Data("corrupt".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("current-hike.json")), bytes)
    }
    @MainActor
    func testMalformedCurrentSurvivesStartupBackgroundPersistAndStart() async throws {
        let root = try directory()
        let original = Data("{malformed original\r\n".utf8)
        let current = root.appendingPathComponent("current-hike.json")
        try original.write(to: current)
        let monitor = HikeMonitor(directory: root)
        monitor.persist() // Same path as the scene background callback / save retry.
        await monitor.start()
        XCTAssertEqual(try Data(contentsOf: current), original)
        XCTAssertNotNil(monitor.saveMessage)
        XCTAssertEqual(monitor.record.state, .idle)
        let snapshots = try RecordExportStore(directory: root.appendingPathComponent("RecordExports")).files()
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(snapshots.first).url), original)
    }

    @MainActor
    func testBackupFailureBlocksPersistAndRecordingStart() async throws {
        let root = try directory()
        let original = try JSONEncoder().encode(HikeRecord())
        let current = root.appendingPathComponent("current-hike.json")
        try original.write(to: current)
        // A file where the backup directory should be forces a real IO failure.
        try Data("blocked".utf8).write(to: root.appendingPathComponent("RecordExports"))
        let monitor = HikeMonitor(directory: root)
        monitor.record.distance = 999
        monitor.persist()
        await monitor.start()
        XCTAssertEqual(try Data(contentsOf: current), original)
        XCTAssertNotNil(monitor.saveMessage)
        XCTAssertEqual(monitor.record.state, .idle)
    }

}
