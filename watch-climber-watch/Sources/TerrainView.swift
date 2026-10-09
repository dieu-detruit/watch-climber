import SwiftUI

struct TerrainView: View {
    let terrain: Terrain
    let fix: Fix?
    let now: Date
    @State private var angle = 0.0
    @State private var zoom = 1.0
    @State private var zoomMode = false
    @FocusState private var crownFocused: Bool

    private var position: (x: Double, y: Double)? {
        guard let fix, fix.usable, now.timeIntervalSince(fix.date) < 30 else { return nil }
        return terrain.grid(latitude: fix.latitude, longitude: fix.longitude)
    }
    private var status: String {
        guard let fix else { return "位置未取得" }
        guard now.timeIntervalSince(fix.date) < 30 else { return "位置更新待ち" }
        guard fix.usable else { return "GPS精度不足" }
        guard let p = position else { return "収録範囲外" }
        guard let h = terrain.height(x: p.x, y: p.y) else { return "地表標高なし" }
        return "地表 \(Int(h))m"
    }
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(status).font(.caption2)
                Spacer()
                Button(zoomMode ? "拡大" : "回転") { zoomMode.toggle(); crownFocused = true }
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(.mint)
            }
            terrainCanvas
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation(zoomMode ? $zoom : $angle,
                                      from: zoomMode ? 0.7 : -180,
                                      through: zoomMode ? 2.5 : 180,
                                      by: zoomMode ? 0.05 : 3,
                                      sensitivity: .low, isContinuous: !zoomMode,
                                      isHapticFeedbackEnabled: true)
            Text("国土地理院 DEM10B 加工").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .onAppear { crownFocused = true }
    }

    private var terrainCanvas: some View {
        Canvas { context, size in
            let center = position ?? (Double(terrain.columns - 1)/2, Double(terrain.rows - 1)/2)
            let base = terrain.height(x: center.0, y: center.1) ?? 2000
            let latitude = fix.flatMap { $0.usable && position != nil ? $0.latitude : nil } ?? (terrain.bounds.north + terrain.bounds.south)/2
            let spacing = terrain.spacing(at: latitude)
            let radius = 60.0 / zoom
            let scale = Double(size.width) / (radius * spacing * 2)
            let radians = angle * .pi / 180
            func project(_ x: Double, _ y: Double, _ height: Double) -> (point: CGPoint, depth: Double) {
                let east = (x - center.0) * spacing, south = (y - center.1) * spacing
                let horizontal = east * cos(radians) - south * sin(radians)
                let depth = east * sin(radians) + south * cos(radians)
                return (CGPoint(x: Double(size.width)/2 + horizontal * scale,
                                y: Double(size.height)*0.55 + (depth*0.5 - (height-base)*0.9)*scale), depth)
            }
            struct Triangle { let points: [CGPoint]; let depth: Double; let height: Double }
            var triangles: [Triangle] = []
            let left = max(0, Int(center.0-radius)), right = min(terrain.columns-1, Int(center.0+radius))
            let top = max(0, Int(center.1-radius)), bottom = min(terrain.rows-1, Int(center.1+radius))
            if left < right && top < bottom {
                for y in stride(from: top, to: bottom, by: 3) {
                    for x in stride(from: left, to: right, by: 3) {
                        let nextX = min(x+3, right), nextY = min(y+3, bottom)
                        let coords = [(x,y), (nextX,y), (x,nextY), (nextX,nextY)]
                        for indices in [[0,1,2], [1,3,2]] {
                            var vertices: [CGPoint] = [], depths: [Double] = [], heights: [Double] = []
                            for index in indices {
                                let (gx,gy) = coords[index]
                                if let height = terrain.heights[gy * terrain.columns + gx] {
                                    let p = project(Double(gx), Double(gy), height)
                                    vertices.append(p.point); depths.append(p.depth); heights.append(height)
                                }
                            }
                            if vertices.count == 3 { triangles.append(Triangle(points: vertices, depth: depths.reduce(0,+)/3, height: heights.reduce(0,+)/3)) }
                        }
                    }
                }
            }
            for triangle in triangles.sorted(by: { $0.depth < $1.depth }) {
                var path = Path()
                path.addLines(triangle.points)
                path.closeSubpath()
                let level = min(1, max(0, (triangle.height-700)/2200))
                context.fill(path, with: .color(Color(hue: 0.43-level*0.12, saturation: 0.5-level*0.25, brightness: 0.28+level*0.5)))
                context.stroke(path, with: .color(.black.opacity(0.16)), lineWidth: 0.3)
            }
            if let p = position, let height = terrain.height(x: p.x, y: p.y) {
                let point = project(p.x, p.y, height).point
                let marker = CGRect(x: point.x-4, y: point.y-4, width: 8, height: 8)
                context.fill(Path(ellipseIn: marker), with: .color(.mint))
                context.stroke(Path(ellipseIn: marker), with: .color(.white), lineWidth: 1.5)
            }
            // North rotates with the same east/south transform as the mesh.
            let origin = CGPoint(x: 18, y: 24)
            let end = CGPoint(x: 18 + sin(radians)*12, y: 24-cos(radians)*6)
            var north = Path(); north.move(to: origin); north.addLine(to: end)
            context.stroke(north, with: .color(.white), lineWidth: 2)
            context.draw(Text("N").font(.system(size: 9)), at: CGPoint(x: end.x, y: end.y-7))
        }
        .accessibilityLabel("五竜の3D地形。\(status)。Digital Crownで\(zoomMode ? "拡大縮小" : "回転")")
    }
}
