import Foundation
import CryptoKit

/// Offline, user-provided GPX routes; never derived from the schematic map.
enum ImportedRouteError: LocalizedError {
    case invalid, outOfRegion, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalid: return "有効な登山ルートを読み込めません"
        case .outOfRegion: return "飯能周辺の地形データから外れたGPXです"
        case .tooLarge: return "GPXデータが大きすぎます"
        }
    }
}

enum ImportedRouteStore {
    static let filename = "hanno-imported-route.json"
    static let id = "hanno-user-gpx"
    static let routeChanged = Notification.Name("WatchClimberImportedRouteChanged")

    static func destination() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    static func validate(_ data: Data) throws -> PlannedRoute {
        guard data.count <= 2_000_000 else { throw ImportedRouteError.tooLarge }
        let route = try JSONDecoder().decode(PlannedRoute.self, from: data)
        guard route.id == id, route.points.count <= 5000, route.totalM < 100_000,
              route.points.count >= 2,
              let bounds = Terrain.load(named: "hanno")?.bounds else {
            throw ImportedRouteError.invalid
        }
        // The offline renderer can only display points within its DEM coverage.
        guard route.points.allSatisfy({
            $0.latitude >= bounds.south && $0.latitude <= bounds.north &&
            $0.longitude >= bounds.west && $0.longitude <= bounds.east
        }) else { throw ImportedRouteError.outOfRegion }
        return route
    }

    static func load() -> PlannedRoute? {
        guard let data = try? Data(contentsOf: destination()) else { return nil }
        return try? validate(data)
    }

    static func save(_ data: Data) throws {
        _ = try validate(data)
        let path = destination()
        if FileManager.default.fileExists(atPath: path.path) {
            let previous = try Data(contentsOf: path)
            if previous != data {
                let backup = path.deletingLastPathComponent()
                    .appendingPathComponent("hanno-route-backup-\(UUID().uuidString).json")
                try previous.write(to: backup, options: .atomic)
            }
        }
        try data.write(to: path, options: .atomic)
        NotificationCenter.default.post(name: routeChanged, object: nil)
    }
}
