import Foundation

/// View selection only. Never resets or writes hike records.
enum MountainSelection: String, CaseIterable, Identifiable {
    case automatic, hanno, goryu

    static let preferenceKey = "watchclimber.selected-mountain"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "GPSで自動"
        case .hanno: return "飯能"
        case .goryu: return "五竜岳"
        }
    }

    static func load() -> MountainSelection {
        guard let stored = UserDefaults.standard.string(forKey: preferenceKey),
              let choice = MountainSelection(rawValue: stored) else { return .automatic }
        return choice
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.preferenceKey)
    }

    /// Selection stays stable when manually fixed, even while recording elsewhere.
    /// In automatic mode only a fresh, usable fix can switch mountain.
    func terrain(from options: [Terrain], fix: Fix?, now: Date = Date()) -> Terrain? {
        let hanno = options.first { $0.name.hasPrefix("飯能") }
        let goryu = options.first { $0.name.hasPrefix("五竜") }
        switch self {
        case .hanno: return hanno
        case .goryu: return goryu
        case .automatic:
            if let fix, fix.usable,
               now.timeIntervalSince(fix.date) >= -5,
               now.timeIntervalSince(fix.date) < 30,
               let found = options.first(where: {
                   $0.grid(latitude: fix.latitude, longitude: fix.longitude) != nil
               }) {
                return found
            }
            return hanno ?? options.first
        }
    }
}
