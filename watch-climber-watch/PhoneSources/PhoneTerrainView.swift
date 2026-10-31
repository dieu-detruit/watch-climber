import SwiftUI

/// Offline 3D DEM view shared in meaning with the Watch screen.
/// Touch replaces the Digital Crown: drag to rotate, pinch to zoom,
/// and tap the drawn route to inspect its position.
struct PhoneTerrainView: View {
    let terrain: Terrain
    let route: PlannedRoute?
    let display: RouteDisplayContext?
    let fix: Fix?
    @Binding var inspection: RouteInspection

    @State private var angle = 0.0
    @State private var zoom = 1.5
    @State private var dragStartAngle: Double?
    @State private var pinchStartZoom: Double?
    @State private var selectedPlace: String?

    private var livePosition: (x: Double, y: Double)? {
        guard let fix, fix.usable,
              Date().timeIntervalSince(fix.date) >= -5,
              Date().timeIntervalSince(fix.date) < 30 else { return nil }
        return terrain.grid(latitude: fix.latitude, longitude: fix.longitude)
    }

    private var inspectedPosition: (x: Double, y: Double)? {
        guard let display, display.isInspecting else { return nil }
        return terrain.grid(latitude: display.position.point.latitude,
                            longitude: display.position.point.longitude)
    }

    private var center: (x: Double, y: Double) {
        if let selected = inspectedPosition { return selected }
        if let selected = livePosition { return selected }
        if let start = route?.points.first,
           let selected = terrain.grid(latitude: start.latitude, longitude: start.longitude) {
            return selected
        }
        return (Double(terrain.columns - 1) / 2, Double(terrain.rows - 1) / 2)
    }

    private var spacing: Double {
        let latitude = fix.flatMap {
            terrain.grid(latitude: $0.latitude, longitude: $0.longitude) != nil ? $0.latitude : nil
        } ?? (terrain.bounds.north + terrain.bounds.south) / 2
        return terrain.spacing(at: latitude)
    }
    private var detail: TerrainDetail { TerrainDetail(spacing: spacing, zoom: zoom) }

    private func project(_ x: Double, _ y: Double, _ height: Double, size: CGSize) -> (point: CGPoint, depth: Double) {
        let centerElevation = terrain.height(x: center.x, y: center.y) ?? 200
        let east = (x - center.x) * spacing
        let south = (y - center.y) * spacing
        let radians = angle * .pi / 180
        let horizontal = east * cos(radians) - south * sin(radians)
        let depth = east * sin(radians) + south * cos(radians)
        let scale = Double(size.width) / (detail.radius * spacing * 2)
        return (CGPoint(x: Double(size.width)/2 + horizontal*scale,
                        y: Double(size.height)*0.55 + (depth*0.5 - (height-centerElevation)*0.9)*scale), depth)
    }

    private func projectGeo(latitude: Double, longitude: Double, size: CGSize) -> CGPoint? {
        guard let p = terrain.grid(latitude: latitude, longitude: longitude),
              let h = terrain.height(x: p.x, y: p.y) else { return nil }
        return project(p.x, p.y, h, size: size).point
    }

    private func select(at location: CGPoint, in size: CGSize) {
        if let route {
            var bestIndex: Int?
            var bestDistance = 36.0
            for (index, point) in route.points.enumerated() {
                guard let p = projectGeo(latitude: point.latitude, longitude: point.longitude, size: size) else { continue }
                let distance = hypot(p.x - location.x, p.y - location.y)
                if distance < bestDistance { bestDistance = distance; bestIndex = index }
            }
            if let bestIndex {
                inspection.inspect(route.distances[bestIndex], totalM: route.totalM)
                selectedPlace = nil
                return
            }
        }
        if terrain.name.hasPrefix("飯能") {
            var nearest: String?
            var bestDistance = 36.0
            for landmark in HannoLandmarks.ordered {
                guard let p = projectGeo(latitude: landmark.latitude, longitude: landmark.longitude, size: size) else { continue }
                let distance = hypot(p.x - location.x, p.y - location.y)
                if distance < bestDistance { nearest = landmark.name; bestDistance = distance }
            }
            selectedPlace = nearest
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(terrain.name).font(.headline)
                Text("国土地理院 DEM10B · オフライン3D")
                    .font(.caption).foregroundStyle(.secondary)
                if let route, let display {
                    HStack {
                        Text(display.isInspecting ? "先読み" : (display.isOnCourse ? "現在付近" : "計画表示"))
                            .foregroundStyle(display.isInspecting ? .orange : .mint)
                        Text(String(format: "%.2f / %.2f km",
                                    display.position.distanceM/1000, route.totalM/1000))
                        Spacer()
                        Text(display.position.point.altitude.map { "計画 \(Int($0)) m" } ?? "計画 — m")
                    }.font(.subheadline.monospacedDigit())
                    if let next = route.nextLandmark(after: display.position.distanceM) {
                        Text("次: \(next.name) · \(Int(max(0, route.landmarkDistance(next)-display.position.distanceM))) m")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("正確な登山ルートは未設定。橙色は地点の位置のみで、道順ではありません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    Canvas { context, size in draw(context, size: size) }
                        .background(.black)
                        .contentShape(Rectangle())
                        .simultaneousGesture(DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                if dragStartAngle == nil { dragStartAngle = angle }
                                angle = (dragStartAngle ?? 0) + Double(value.translation.width) * 0.6
                            }
                            .onEnded { _ in
                                angle = angle.truncatingRemainder(dividingBy: 360)
                                dragStartAngle = nil
                            })
                        .simultaneousGesture(MagnificationGesture()
                            .onChanged { value in
                                if pinchStartZoom == nil { pinchStartZoom = zoom }
                                zoom = min(12, max(0.7, (pinchStartZoom ?? zoom) * Double(value)))
                            }
                            .onEnded { _ in pinchStartZoom = nil })
                        .simultaneousGesture(SpatialTapGesture()
                            .onEnded { value in select(at: value.location, in: geometry.size) })
                        .accessibilityLabel("3D地形。1本指ドラッグで回転、2本指ピンチで拡大縮小、ルートをタップして先読み")
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                Text("ドラッグ：回転　ピンチ：拡大縮小　タップ：ルート／地点選択")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button("北を上") { angle = 0 }
                    Spacer()
                    Button("全体表示") { zoom = 1 }
                    if display?.isInspecting == true {
                        Spacer()
                        Button("GPSへ") { inspection.followGPS() }
                    }
                }.buttonStyle(.bordered)
                if let route, let display {
                    Slider(value: Binding(
                        get: { display.position.distanceM },
                        set: { inspection.inspect($0, totalM: route.totalM) }
                    ), in: 0...max(route.totalM, 1))
                    .accessibilityLabel("ルート先読み位置")
                    Text("指でルートをタップするかスライダーで先読みできます。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let selectedPlace {
                    Label(selectedPlace, systemImage: "mappin")
                        .font(.subheadline)
                }
                if livePosition == nil {
                    Text("現在地の測位なし、または表示中の地形データの範囲外です。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private func draw(_ context: GraphicsContext, size: CGSize) {
        let step = detail.step, radius = detail.radius
        let left = max(0, Int(floor((center.x-radius)/Double(step)))*step)
        let right = min(terrain.columns-1, Int(ceil((center.x+radius)/Double(step)))*step)
        let top = max(0, Int(floor((center.y-radius)/Double(step)))*step)
        let bottom = min(terrain.rows-1, Int(ceil((center.y+radius)/Double(step)))*step)
        struct Triangle { let vertices: [CGPoint]; let depth: Double; let height: Double }
        var faces: [Triangle] = []
        if left < right && top < bottom {
            for y in stride(from: top, to: bottom, by: step) {
                for x in stride(from: left, to: right, by: step) {
                    let x2 = min(x+step,right), y2 = min(y+step,bottom)
                    let corners = [(x,y),(x2,y),(x,y2),(x2,y2)]
                    for indices in [[0,1,2],[1,3,2]] {
                        var vertices: [CGPoint] = [], depths: [Double] = [], elevations: [Double] = []
                        for i in indices {
                            let (gx,gy) = corners[i]
                            guard let height = terrain.heights[gy*terrain.columns+gx] else { continue }
                            let p = project(Double(gx),Double(gy),height,size:size)
                            vertices.append(p.point); depths.append(p.depth); elevations.append(height)
                        }
                        if vertices.count == 3 {
                            faces.append(Triangle(vertices: vertices, depth: depths.reduce(0,+)/3,
                                                  height: elevations.reduce(0,+)/3))
                        }
                    }
                }
            }
        }
        for face in faces.sorted(by: { $0.depth < $1.depth }) {
            var path = Path(); path.addLines(face.vertices); path.closeSubpath()
            let level = min(1,max(0,(face.height-700)/2200))
            context.fill(path,with: .color(Color(hue: 0.43-level*0.12,
                                               saturation: 0.5-level*0.25,brightness: 0.28+level*0.5)))
            context.stroke(path,with:.color(.black.opacity(0.16)),lineWidth:0.3)
        }
        if let route {
            var path=Path(), connected=false
            for point in route.points {
                guard let p=terrain.grid(latitude: point.latitude,longitude: point.longitude),
                      abs(p.x-center.x)<=radius*1.5,
                      abs(p.y-center.y)<=radius*1.5,
                      let h=terrain.height(x:p.x,y:p.y) else { connected=false;continue }
                let projected=project(p.x,p.y,h,size:size).point
                if connected {path.addLine(to:projected)} else {path.move(to:projected)}
                connected=true
            }
            context.stroke(path,with:.color(.black.opacity(0.7)),
                           style:StrokeStyle(lineWidth:5,lineCap:.round,lineJoin:.round))
            context.stroke(path,with:.color(.orange),
                           style:StrokeStyle(lineWidth:2.5,lineCap:.round,lineJoin:.round))
            var named=Set<String>()
            for landmark in route.landmarks where !named.contains(landmark.name) {
                let location=route.landmarkPosition(landmark)
                guard let p=projectGeo(latitude: location.latitude,longitude: location.longitude,size:size),
                      p.x>=10,p.y>=10,p.x<=size.width-10,p.y<=size.height-10 else {continue}
                named.insert(landmark.name)
                context.draw(Text(landmark.shortName).font(.system(size:10)).foregroundColor(.white),
                             at:CGPoint(x:p.x,y:p.y-12))
                if named.count>=8 {break}
            }
        } else if terrain.name.hasPrefix("飯能") {
            for landmark in HannoLandmarks.ordered {
                guard let p=projectGeo(latitude:landmark.latitude,longitude:landmark.longitude,size:size),
                      p.x>=6,p.y>=6,p.x<=size.width-6,p.y<=size.height-6 else {continue}
                context.fill(Path(ellipseIn:CGRect(x:p.x-4,y:p.y-4,width:8,height:8)),with:.color(.orange))
                context.draw(Text(landmark.shortName).font(.system(size:11)).foregroundColor(.white),
                             at:CGPoint(x:p.x,y:p.y-13))
            }
        }
        if let p=inspectedPosition,
           let h=terrain.height(x:p.x,y:p.y) {
            let point=project(p.x,p.y,h,size:size).point
            let marker=Path(ellipseIn:CGRect(x:point.x-6,y:point.y-6,width:12,height:12))
            context.fill(marker,with:.color(.orange))
            context.stroke(marker,with:.color(.white),lineWidth:2)
        }
        if let p=livePosition,let h=terrain.height(x:p.x,y:p.y) {
            let point=project(p.x,p.y,h,size:size).point
            let marker=Path(ellipseIn:CGRect(x:point.x-6,y:point.y-6,width:12,height:12))
            context.fill(marker,with:.color(.mint))
            context.stroke(marker,with:.color(.white),lineWidth:2)
        }
        context.draw(Text("N").font(.caption2).foregroundColor(.white),
                     at:CGPoint(x:20,y:20))
    }
}
