import Foundation

struct Terrain: Decodable {
    struct Bounds: Decodable { let west, east, north, south: Double }
    let name: String
    let columns, rows: Int
    let bounds: Bounds
    let heights: [Double?]
    let heightRange: [Double]

    static func load() -> Terrain? {
        guard let url = Bundle.main.url(forResource: "goryu", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let terrain = try? JSONDecoder().decode(Self.self, from: data),
              terrain.columns >= 2, terrain.rows >= 2,
              terrain.heights.count == terrain.columns * terrain.rows,
              terrain.heightRange.count == 2 else { return nil }
        return terrain
    }

    func grid(latitude: Double, longitude: Double) -> (x: Double, y: Double)? {
        guard latitude.isFinite, longitude.isFinite,
              latitude >= bounds.south, latitude <= bounds.north,
              longitude >= bounds.west, longitude <= bounds.east else { return nil }
        func mercator(_ lat: Double) -> Double { asinh(tan(lat * .pi / 180)) }
        return ((longitude - bounds.west) / (bounds.east - bounds.west) * Double(columns - 1),
                (mercator(bounds.north) - mercator(latitude)) / (mercator(bounds.north) - mercator(bounds.south)) * Double(rows - 1))
    }

    func height(x: Double, y: Double) -> Double? {
        guard x.isFinite, y.isFinite, x >= 0, y >= 0, x <= Double(columns - 1), y <= Double(rows - 1) else { return nil }
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let x1 = min(x0 + 1, columns - 1), y1 = min(y0 + 1, rows - 1)
        guard let a = heights[y0 * columns + x0], let b = heights[y0 * columns + x1],
              let c = heights[y1 * columns + x0], let d = heights[y1 * columns + x1] else { return nil }
        let fx = x - Double(x0), fy = y - Double(y0)
        return (a * (1-fx) + b * fx) * (1-fy) + (c * (1-fx) + d * fx) * fy
    }

    func spacing(at latitude: Double) -> Double {
        (bounds.east - bounds.west) * .pi / 180 * 6_378_137 * cos(latitude * .pi / 180) / Double(columns - 1)
    }
}

struct TerrainDetail {
    let radius: Double
    let step: Int
    init(spacing: Double, zoom: Double) {
        radius = 3660 / max(0.7, min(12, zoom)) / spacing
        step = Int(pow(2.0, max(0, ceil(log2(2 * radius / 80)))))
    }
}
