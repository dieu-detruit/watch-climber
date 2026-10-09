import SwiftUI

enum TerrainCrownMode: Int, CaseIterable {
    case inspect, rotate, zoom
    var label: String {
        switch self { case .inspect: return "先読み"; case .rotate: return "回転"; case .zoom: return "拡大" }
    }
}

struct TerrainView: View {
    let terrain: Terrain
    let route: PlannedRoute?
    let display: RouteDisplayContext?
    let fix: Fix?
    let now: Date
    let isActive: Bool
    @Binding var inspection: RouteInspection
    @Binding var angle: Double
    @Binding var zoom: Double
    @Binding var crownMode: TerrainCrownMode
    @FocusState private var crownFocused: Bool

    private var position: (x: Double, y: Double)? {
        guard let fix, fix.usable, now.timeIntervalSince(fix.date) >= -5,
              now.timeIntervalSince(fix.date) < 30 else { return nil }
        return terrain.grid(latitude: fix.latitude, longitude: fix.longitude)
    }
    private var inspectedPosition: (x: Double, y: Double)? {
        guard let display, display.isInspecting else { return nil }
        return terrain.grid(latitude: display.position.point.latitude, longitude: display.position.point.longitude)
    }
    private var planStart: (x: Double, y: Double)? {
        guard let start = route?.points.first else { return nil }
        return terrain.grid(latitude: start.latitude, longitude: start.longitude)
    }
    private var status: String {
        guard let fix else { return "GPS未取得 · 計画表示" }
        guard now.timeIntervalSince(fix.date) >= -5, now.timeIntervalSince(fix.date) < 30 else { return "GPS更新待ち" }
        guard fix.usable else { return "GPS精度不足" }
        guard position != nil else { return "GPSは地形収録範囲外" }
        if let display, !display.isOnCourse { return "GPSはコース外" }
        return display?.isInspecting == true ? "橙: 先読み · 緑: GPS" : "緑: 実際のGPS位置"
    }
    private var meshSpacing: Int {
        let spacing = terrain.spacing(at: (terrain.bounds.north + terrain.bounds.south) / 2)
        return Int((spacing * Double(TerrainDetail(spacing: spacing, zoom: zoom).step)).rounded())
    }
    private var crownValue: Binding<Double> {
        switch crownMode {
        case .inspect:
            return Binding(get: { display?.position.distanceM ?? 0 }, set: { inspection.inspect($0, totalM: route?.totalM ?? 0) })
        case .rotate: return $angle
        case .zoom: return $zoom
        }
    }
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Button { inspection.followGPS(); crownFocused = true } label: {
                    Text("GPSへ").frame(minWidth: 44, minHeight: 26).contentShape(Rectangle())
                }
                    .disabled(!((display?.isInspecting) ?? false))
                Spacer()
                Button {
                    crownMode = TerrainCrownMode(rawValue: (crownMode.rawValue + 1) % 3) ?? .inspect
                    if route == nil && crownMode == .inspect { crownMode = .rotate }
                    crownFocused = true
                } label: {
                    Text("Crown: " + crownMode.label).frame(minWidth: 44, minHeight: 26).contentShape(Rectangle())
                }
            }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.mint)
            if let route, let display { RoutePositionSummary(route: route, display: display) }
            terrainCanvas
                .clipped()
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation(crownValue,
                                      from: crownMode == .zoom ? 0.7 : (crownMode == .rotate ? -180 : 0),
                                      through: crownMode == .zoom ? 12 : (crownMode == .rotate ? 180 : max(1, route?.totalM ?? 1)),
                                      by: crownMode == .zoom ? 0.1 : (crownMode == .rotate ? 3 : 50),
                                      sensitivity: .low, isContinuous: crownMode == .rotate,
                                      isHapticFeedbackEnabled: true)
            Text(status).font(.system(size: 9)).foregroundStyle(.secondary)
            Text("\(meshSpacing)m · 国土地理院 DEM10B / YAMAP").font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .onAppear {
            if route == nil && crownMode == .inspect { crownMode = .rotate }
            crownFocused = isActive
        }
        .onChange(of: isActive) { _, active in crownFocused = active }
    }

    private var terrainCanvas: some View {
        Canvas { context, size in
            let center = inspectedPosition ?? position ?? planStart ?? (Double(terrain.columns - 1)/2, Double(terrain.rows - 1)/2)
            let base = terrain.height(x: center.0, y: center.1) ?? 2000
            let latitude = fix.flatMap { $0.usable && position != nil ? $0.latitude : nil } ?? (terrain.bounds.north + terrain.bounds.south)/2
            let spacing = terrain.spacing(at: latitude)
            let detail = TerrainDetail(spacing: spacing, zoom: zoom)
            let radius = detail.radius, step = detail.step
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
            let left = max(0, Int(floor((center.0-radius)/Double(step))) * step), right = min(terrain.columns-1, Int(ceil((center.0+radius)/Double(step))) * step)
            let top = max(0, Int(floor((center.1-radius)/Double(step))) * step), bottom = min(terrain.rows-1, Int(ceil((center.1+radius)/Double(step))) * step)
            if left < right && top < bottom {
                for y in stride(from: top, to: bottom, by: step) {
                    for x in stride(from: left, to: right, by: step) {
                        let nextX = min(x+step, right), nextY = min(y+step, bottom)
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
            if let route {
                var path = Path()
                var connected = false
                for point in route.points {
                    guard let p = terrain.grid(latitude: point.latitude, longitude: point.longitude),
                          abs(p.x - center.0) <= radius * 1.5, abs(p.y - center.1) <= radius * 1.5,
                          let height = terrain.height(x: p.x, y: p.y) else { connected = false; continue }
                    let projected = project(p.x, p.y, height).point
                    if connected { path.addLine(to: projected) } else { path.move(to: projected) }
                    connected = true
                }
                context.stroke(path, with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                var usedNames = Set<String>()
                var occupied: [CGRect] = []
                // Summit and hut remain recognizable; cap and deconflict labels for the watch screen.
                let landmarks = route.landmarks.sorted {
                    let a = ($0.name == "五竜岳" || $0.name == "五竜山荘テント場") ? 0 : 1
                    let b = ($1.name == "五竜岳" || $1.name == "五竜山荘テント場") ? 0 : 1
                    return a < b
                }
                for landmark in landmarks {
                    guard !usedNames.contains(landmark.name), occupied.count < 5 else { continue }
                    let point = route.landmarkPosition(landmark)
                    guard let p = terrain.grid(latitude: point.latitude, longitude: point.longitude),
                          abs(p.x - center.0) <= radius, abs(p.y - center.1) <= radius,
                          let height = terrain.height(x: p.x, y: p.y) else { continue }
                    let projected = project(p.x, p.y, height).point
                    let name = landmark.name == "五竜山荘テント場" ? "五竜山荘" : landmark.shortName
                    let width = min(Double(size.width) - 8, Double(name.count) * 9 + 8)
                    let x = max(width / 2 + 2, min(Double(size.width) - width / 2 - 2, Double(projected.x)))
                    let y = Double(projected.y) - 12
                    guard y > 7, y < Double(size.height) - 8, projected.x >= 0, projected.x <= size.width else { continue }
                    let rect = CGRect(x: x - width / 2, y: y - 7, width: width, height: 14)
                    guard !occupied.contains(where: { $0.intersects(rect.insetBy(dx: -2, dy: -2)) }) else { continue }
                    usedNames.insert(landmark.name); occupied.append(rect)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.black.opacity(0.65)))
                    context.draw(Text(name).font(.system(size: 9)).foregroundColor(.white), at: CGPoint(x: x, y: y))
                }
            }
            if let p = inspectedPosition, let height = terrain.height(x: p.x, y: p.y) {
                let point = project(p.x, p.y, height).point
                let marker = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                context.fill(marker, with: .color(.orange))
                context.stroke(marker, with: .color(.white), lineWidth: 1.5)
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
        .accessibilityLabel("五竜の3D地形。\(status)。Digital Crownで\(crownMode.label)")
    }
}
