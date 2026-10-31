import SwiftUI

/// The same bundled GSI DEM as the Watch, with touch controls instead of Crown.
struct PhoneTerrainView: View {
    let terrain: Terrain
    let fix: Fix?
    @State private var angle = 0.0
    @State private var zoom = 1.5

    private var position: (x: Double, y: Double)? {
        guard let fix, fix.usable, Date().timeIntervalSince(fix.date) < 30 else { return nil }
        return terrain.grid(latitude: fix.latitude, longitude: fix.longitude)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("\(terrain.name) · 国土地理院DEM10B")
                .font(.subheadline).foregroundStyle(.secondary)
            Canvas { context, size in
                let center = position ?? (Double(terrain.columns - 1) / 2, Double(terrain.rows - 1) / 2)
                let base = terrain.height(x: center.0, y: center.1) ?? 2000
                let latitude = fix.flatMap { terrain.grid(latitude: $0.latitude, longitude: $0.longitude) != nil ? $0.latitude : nil } ??
                    (terrain.bounds.north + terrain.bounds.south) / 2
                let spacing = terrain.spacing(at: latitude)
                let detail = TerrainDetail(spacing: spacing, zoom: zoom)
                let radians = angle * .pi / 180
                let scale = Double(size.width) / (detail.radius * spacing * 2)
                func project(_ x: Double, _ y: Double, _ h: Double) -> (CGPoint, Double) {
                    let east = (x - center.0) * spacing, south = (y - center.1) * spacing
                    let horizontal = east * cos(radians) - south * sin(radians)
                    let depth = east * sin(radians) + south * cos(radians)
                    return (CGPoint(x: Double(size.width)/2 + horizontal*scale,
                                    y: Double(size.height)*0.55 + (depth*0.5 - (h-base)*0.9)*scale), depth)
                }
                struct Triangle { let vertices: [CGPoint]; let depth, height: Double }
                var faces: [Triangle] = []
                let step = detail.step, radius = detail.radius
                let left = max(0, Int(floor((center.0-radius)/Double(step))) * step)
                let right = min(terrain.columns-1, Int(ceil((center.0+radius)/Double(step))) * step)
                let top = max(0, Int(floor((center.1-radius)/Double(step))) * step)
                let bottom = min(terrain.rows-1, Int(ceil((center.1+radius)/Double(step))) * step)
                if left < right && top < bottom {
                    for y in stride(from: top, to: bottom, by: step) {
                        for x in stride(from: left, to: right, by: step) {
                            let nextX = min(x+step, right), nextY = min(y+step, bottom)
                            let coords = [(x,y), (nextX,y), (x,nextY), (nextX,nextY)]
                            for indices in [[0,1,2],[1,3,2]] {
                                var vertices: [CGPoint] = [], depths: [Double] = [], heights: [Double] = []
                                for i in indices {
                                    let (gx,gy) = coords[i]
                                    guard let h = terrain.heights[gy * terrain.columns + gx] else { continue }
                                    let (p, depth) = project(Double(gx), Double(gy), h)
                                    vertices.append(p); depths.append(depth); heights.append(h)
                                }
                                if vertices.count == 3 {
                                    faces.append(Triangle(vertices: vertices,
                                                          depth: depths.reduce(0,+)/3, height: heights.reduce(0,+)/3))
                                }
                            }
                        }
                    }
                }
                for face in faces.sorted(by: { $0.depth < $1.depth }) {
                    var path = Path(); path.addLines(face.vertices); path.closeSubpath()
                    let level = min(1, max(0, (face.height - 700) / 2200))
                    context.fill(path, with: .color(Color(hue: 0.43-level*0.12, saturation: 0.5-level*0.25, brightness: 0.28+level*0.5)))
                    context.stroke(path, with: .color(.black.opacity(0.16)), lineWidth: 0.3)
                }
                if terrain.name.hasPrefix("飯能") {
                    for landmark in HannoLandmarks.ordered {
                        guard let p = terrain.grid(latitude: landmark.latitude, longitude: landmark.longitude),
                              let height = terrain.height(x: p.x, y: p.y) else { continue }
                        let (point, _) = project(p.x, p.y, height)
                        let dot = Path(ellipseIn: CGRect(x: point.x-4, y: point.y-4, width: 8, height: 8))
                        context.fill(dot, with: .color(.orange))
                        context.draw(Text(landmark.shortName).font(.system(size: 11)).foregroundColor(.white),
                                     at: CGPoint(x: point.x, y: point.y - 13))
                    }
                }
                if let p = position, let height = terrain.height(x: p.x, y: p.y) {
                    let (point, _) = project(p.x, p.y, height)
                    let dot = Path(ellipseIn: CGRect(x: point.x-6, y: point.y-6, width: 12, height: 12))
                    context.fill(dot, with: .color(.mint))
                    context.stroke(dot, with: .color(.white), lineWidth: 2)
                }
            }
            .frame(height: 360)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                Text("回転")
                Slider(value: $angle, in: -180...180)
            }
            HStack {
                Text("拡大")
                Slider(value: $zoom, in: 0.7...12)
            }
            Text(position == nil ? "現在地は表示中の地形範囲外、またはGPS未取得です。" : "緑: iPhoneのGPS現在地 · 橙: 名所（道順ではありません）")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}
