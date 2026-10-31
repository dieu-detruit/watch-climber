import Foundation

/// Turns a verified Watch JSON snapshot into a paused, appendable iPhone record.
/// No time or distance is synthesized for the period between devices.
enum HikeContinuationError: LocalizedError {
    case notRunning, invalidRecord

    var errorDescription: String? {
        switch self {
        case .notRunning: return "終了済み・未開始のWatch記録は引き継げません"
        case .invalidRecord: return "Watch記録の内容を検証できません"
        }
    }
}

enum HikeContinuation {
    static func restore(_ data: Data) throws -> HikeRecord {
        guard data.count <= 40_000_000 else { throw HikeContinuationError.invalidRecord }
        var record = try JSONDecoder().decode(HikeRecord.self, from: data)
        guard record.state == .recording || record.state == .paused else {
            throw HikeContinuationError.notRunning
        }
        guard record.elapsed.isFinite, record.elapsed >= 0,
              record.distance.isFinite, record.distance >= 0,
              record.ascent.isFinite, record.ascent >= 0,
              record.points.count <= 200_000,
              record.points.allSatisfy({ $0.fix.usable && ($0.fix.altitude?.isFinite ?? true) })
        else { throw HikeContinuationError.invalidRecord }
        record.prepareAfterRestore()
        return record
    }
}
