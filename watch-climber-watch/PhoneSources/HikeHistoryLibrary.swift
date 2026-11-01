import Foundation

/// Read-only index of all hike JSON files. No cleanup, rename, or consolidation of originals.
enum HikeHistorySource: String {
    case phone
    case watch

    var label: String {
        switch self {
        case .phone: return "iPhone"
        case .watch: return "Watch"
        }
    }
}

struct HikeHistoryEntry: Identifiable {
    let url: URL
    let source: HikeHistorySource
    let originalName: String
    let digest: String
    let hikeID: UUID
    let firstFixAt: Date?
    let lastFixAt: Date?
    let fileDate: Date
    let elapsed: Double
    let distance: Double
    let ascent: Double
    let pointsCount: Int
    let state: HikeRecord.State

    var id: String { url.path + "#" + digest }
    var displayedDate: Date { firstFixAt ?? fileDate }
    var isCurrentPhone: Bool { source == .phone && originalName == "current-phone-hike.json" }
}

struct HikeHistoryGroup: Identifiable {
    let hikeID: UUID
    let source: HikeHistorySource
    let revisions: [HikeHistoryEntry]

    var id: String { source.rawValue + ":" + hikeID.uuidString }
    var latest: HikeHistoryEntry { revisions[0] }
    var older: [HikeHistoryEntry] { Array(revisions.dropFirst()) }
}

enum HikeHistoryLibrary {
    static func phoneEntries(in documents: URL) -> [HikeHistoryEntry] {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url -> HikeHistoryEntry? in
            let name = url.lastPathComponent
            guard name == "current-phone-hike.json"
                    || (name.hasPrefix("phone-hike-") && name.hasSuffix(".json"))
                    || (name.hasPrefix("phone-before-import-") && name.hasSuffix(".json")) else { return nil }
            return try? loadEntry(url: url, source: .phone, originalName: name)
        }
    }

    static func watchEntries(from files: [RecordExportFile]) -> [HikeHistoryEntry] {
        files.compactMap { file in
            try? loadEntry(url: file.url, source: .watch,
                           originalName: file.originalName, expectedDigest: file.sha256)
        }
    }

    static func groups(_ entries: [HikeHistoryEntry]) -> [HikeHistoryGroup] {
        let byID = Dictionary(grouping: entries, by: \.hikeID)
        return byID.map { id, snapshots in
            var uniqueDigests = Set<String>()
            let revisions = snapshots.sorted(by: newer).filter { uniqueDigests.insert($0.digest).inserted }
            return HikeHistoryGroup(hikeID: id, source: snapshots[0].source, revisions: revisions)
        }.sorted {
            ($0.latest.lastFixAt ?? $0.latest.fileDate) >
                ($1.latest.lastFixAt ?? $1.latest.fileDate)
        }
    }

    /// Validate the file at view time, not only when indexing, because it may have changed.
    static func read(_ entry: HikeHistoryEntry) throws -> HikeRecord {
        let bytes = try Data(contentsOf: entry.url)
        guard bytes.count <= 40_000_000,
              RecordExportFile.digest(bytes) == entry.digest else {
            throw RecordExportError.integrityMismatch
        }
        let record = try JSONDecoder().decode(HikeRecord.self, from: bytes)
        guard record.id == entry.hikeID, record.elapsed.isFinite, record.elapsed >= 0,
              record.distance.isFinite, record.distance >= 0,
              record.ascent.isFinite, record.ascent >= 0,
              record.points.count <= 200_000,
              record.points.allSatisfy({
                  $0.fix.usable && ($0.fix.altitude?.isFinite ?? true)
              }) else {
            throw HikeContinuationError.invalidRecord
        }
        return record
    }

    private static func loadEntry(url: URL, source: HikeHistorySource,
                                  originalName: String, expectedDigest: String? = nil) throws -> HikeHistoryEntry {
        let props = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
        guard props.isRegularFile == true, props.isSymbolicLink != true else {
            throw RecordExportError.invalidFile
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 40_000_000 else { throw HikeContinuationError.invalidRecord }
        let digest = RecordExportFile.digest(data)
        if let expectedDigest, expectedDigest != digest { throw RecordExportError.integrityMismatch }
        let record = try JSONDecoder().decode(HikeRecord.self, from: data)
        guard record.elapsed.isFinite, record.elapsed >= 0, record.distance.isFinite,
              record.distance >= 0, record.ascent.isFinite, record.ascent >= 0,
              record.points.count <= 200_000,
              record.points.allSatisfy({
                  $0.fix.usable && ($0.fix.altitude?.isFinite ?? true)
              }) else { throw HikeContinuationError.invalidRecord }
        if record.state == .idle && record.points.isEmpty && record.elapsed == 0 { throw HikeContinuationError.invalidRecord }
        return HikeHistoryEntry(
            url: url, source: source, originalName: originalName,
            digest: digest, hikeID: record.id,
            firstFixAt: record.points.first?.fix.date, lastFixAt: record.points.last?.fix.date,
            fileDate: props.contentModificationDate ?? .distantPast,
            elapsed: record.elapsed, distance: record.distance, ascent: record.ascent,
            pointsCount: record.points.count, state: record.state
        )
    }

    private static func newer(_ lhs: HikeHistoryEntry, _ rhs: HikeHistoryEntry) -> Bool {
        // Use recorded elapsed time, NOT transfer arrival time; WCSession can arrive out of order.
        if lhs.elapsed != rhs.elapsed { return lhs.elapsed > rhs.elapsed }
        if lhs.pointsCount != rhs.pointsCount { return lhs.pointsCount > rhs.pointsCount }
        if lhs.state != rhs.state { return lhs.state == .finished }
        return lhs.fileDate > rhs.fileDate
    }
}
