import Foundation
import CryptoKit

/// Raw recovery files. Never decode HikeRecord or modify its source files here.
struct RecordExportFile: Identifiable {
    let url: URL
    let originalName: String
    let sha256: String
    let byteCount: Int
    var id: String { "\(originalName)--\(sha256)" }
    var metadata: [String: Any] {
        ["kind": "record", "version": 1, "originalName": originalName,
         "sha256": sha256, "byteCount": byteCount]
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func metadata(originalName: String, data: Data) -> [String: Any] {
        ["kind": "record", "version": 1, "originalName": originalName,
         "sha256": digest(data), "byteCount": data.count]
    }
    static func validOriginalName(_ name: String) -> Bool {
        guard name.utf8.count <= 160, name == (name as NSString).lastPathComponent,
              name == "current-hike.json" || (name.hasPrefix("hike-") && name.hasSuffix(".json")) else { return false }
        return name.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0) }
    }
    static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

enum RecordExportError: LocalizedError {
    case invalidFile, integrityMismatch
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "記録ファイルの名前・形式を確認できません"
        case .integrityMismatch: return "記録のサイズ・SHA-256が一致しません。原本を残して再試行してください"
        }
    }
}

/// Used synchronously from WCSession's receive delegate so its temporary URL is
/// copied into durable app storage before the delegate returns.
final class RecordExportStore {
    let directory: URL
    private let lock = NSRecursiveLock()
    private let manager = FileManager.default
    init(directory: URL) { self.directory = directory }

    func snapshotRecords(in sourceDirectory: URL) throws -> [RecordExportFile] {
        lock.lock(); defer { lock.unlock() }
        let sources = try manager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        for source in sources where RecordExportFile.validOriginalName(source.lastPathComponent) {
            try requireRegularFile(source)
            let bytes = try Data(contentsOf: source)
            _ = try save(bytes, originalName: source.lastPathComponent)
        }
        // Include earlier snapshots, even after a new hike replaces current-hike.
        return try files()
    }

    func receive(temporaryURL: URL, metadata: [String: Any]) throws -> RecordExportFile {
        lock.lock(); defer { lock.unlock() }
        guard metadata["kind"] as? String == "record", metadata["version"] as? Int == 1,
              let name = metadata["originalName"] as? String, RecordExportFile.validOriginalName(name),
              let digest = metadata["sha256"] as? String, RecordExportFile.validDigest(digest),
              let count = metadata["byteCount"] as? Int, count >= 0 else { throw RecordExportError.invalidFile }
        try requireRegularFile(temporaryURL)
        let bytes = try Data(contentsOf: temporaryURL)
        guard bytes.count == count, RecordExportFile.digest(bytes) == digest else { throw RecordExportError.integrityMismatch }
        return try save(bytes, originalName: name)
    }

    func files() throws -> [RecordExportFile] {
        lock.lock(); defer { lock.unlock() }
        guard manager.fileExists(atPath: directory.path) else { return [] }
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.pathExtension == "json" }
            .map { url in
                try requireRegularFile(url)
                let stem = url.deletingPathExtension().lastPathComponent
                guard let separator = stem.range(of: "--", options: .backwards) else { throw RecordExportError.invalidFile }
                let name = String(stem[..<separator.lowerBound]) + ".json"
                let digest = String(stem[separator.upperBound...])
                guard RecordExportFile.validOriginalName(name), RecordExportFile.validDigest(digest) else { throw RecordExportError.invalidFile }
                let bytes = try Data(contentsOf: url)
                guard RecordExportFile.digest(bytes) == digest else { throw RecordExportError.integrityMismatch }
                return RecordExportFile(url: url, originalName: name, sha256: digest, byteCount: bytes.count)
            }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    private func requireRegularFile(_ url: URL) throws {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else { throw RecordExportError.invalidFile }
    }

    private func save(_ bytes: Data, originalName: String) throws -> RecordExportFile {
        guard RecordExportFile.validOriginalName(originalName) else { throw RecordExportError.invalidFile }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = RecordExportFile.digest(bytes)
        let stem = (originalName as NSString).deletingPathExtension
        let destination = directory.appendingPathComponent("\(stem)--\(digest).json")
        if manager.fileExists(atPath: destination.path) {
            try requireRegularFile(destination)
            guard try Data(contentsOf: destination) == bytes else { throw RecordExportError.integrityMismatch }
        } else {
            try bytes.write(to: destination, options: .atomic)
        }
        // Only a durable copy verified after writing can be acknowledged.
        let saved = try Data(contentsOf: destination)
        guard saved.count == bytes.count, RecordExportFile.digest(saved) == digest else { throw RecordExportError.integrityMismatch }
        return RecordExportFile(url: destination, originalName: originalName, sha256: digest, byteCount: bytes.count)
    }
}
