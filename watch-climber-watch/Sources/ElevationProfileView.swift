import SwiftUI

struct ElevationProfileView: View {
    let route: PlannedRoute
    let display: RouteDisplayContext
    let isActive: Bool
    @Binding var inspection: RouteInspection
    @FocusState private var crownFocused: Bool

    private var distance: Binding<Double> {
        Binding(get: { display.position.distanceM },
                set: { inspection.inspect($0, totalM: route.totalM) })
    }
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text("コース断面").font(.caption)
                Spacer()
                Button { inspection.followGPS(); crownFocused = true } label: {
                    Text("GPSへ").frame(minWidth: 44, minHeight: 26).contentShape(Rectangle())
                }
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(.mint)
                    .disabled(!display.isInspecting)
            }
            RoutePositionSummary(route: route, display: display)
            profile
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation(distance, from: 0, through: route.totalM, by: 50,
                                      sensitivity: .low, isContinuous: false,
                                      isHapticFeedbackEnabled: true)
            HStack {
                Text("0km")
                Spacer()
                Text(String(format: "%.1fkm", route.totalM / 1000))
            }.font(.system(size: 9)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Button { jumpLandmark(forward: false) } label: {
                    Image(systemName: "chevron.left").frame(width: 32, height: 26).contentShape(Rectangle())
                }
                    .accessibilityLabel("前の地点")
                Text(nearbyLandmarkName).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                Button { jumpLandmark(forward: true) } label: {
                    Image(systemName: "chevron.right").frame(width: 32, height: 26).contentShape(Rectangle())
                }
                    .accessibilityLabel("次の地点")
            }.buttonStyle(.plain).foregroundStyle(.orange)
            Text("橙: 先読み · 緑: GPSのコース上目安")
                .font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .onAppear { crownFocused = isActive }
        .onChange(of: isActive) { _, active in crownFocused = active }
    }

    private var nearbyLandmarkName: String {
        route.landmarks.min(by: {
            abs(route.landmarkDistance($0) - display.position.distanceM) < abs(route.landmarkDistance($1) - display.position.distanceM)
        })?.name ?? route.name
    }
    private func jumpLandmark(forward: Bool) {
        let selected = display.position.distanceM
        let candidates = route.landmarks.filter {
            forward ? route.landmarkDistance($0) > selected + 1 : route.landmarkDistance($0) < selected - 1
        }
        if let landmark = forward ? candidates.first : candidates.last {
            inspection.inspect(route.landmarkDistance(landmark), totalM: route.totalM)
        }
        crownFocused = true
    }

    private var profile: some View {
        Canvas { context, size in
            let elevations = route.points.compactMap(\.altitude)
            guard let low = elevations.min(), let high = elevations.max() else { return }
            let bottom = Double(size.height) - 2
            let top = min(25.0, Double(size.height) * 0.3)
            let span = max(1, high - low)
            func project(_ distance: Double, _ altitude: Double) -> CGPoint {
                CGPoint(x: 2 + distance / route.totalM * max(1, Double(size.width) - 4),
                        y: bottom - (altitude - low) / span * max(1, bottom - top))
            }
            for level in [low, high] {
                let y = project(0, level).y
                var grid = Path(); grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
                context.draw(Text("\(Int(level))m").font(.system(size: 8)).foregroundColor(.secondary),
                             at: CGPoint(x: 2, y: y - 2), anchor: .bottomLeading)
            }
            var line = Path()
            var connected = false
            for (index, point) in route.points.enumerated() {
                guard let altitude = point.altitude else { connected = false; continue }
                let p = project(route.distances[index], altitude)
                if connected { line.addLine(to: p) } else { line.move(to: p) }
                connected = true
            }
            context.stroke(line, with: .color(.white.opacity(0.9)), lineWidth: 1.8)
            // The two hut visits remain separate along the out-and-back distance axis.
            for landmark in route.landmarks where landmark.name == "五竜岳" || landmark.name == "五竜山荘テント場" {
                let distance = route.landmarkDistance(landmark)
                guard let altitude = route.position(at: distance).point.altitude else { continue }
                let p = project(distance, altitude)
                let summit = landmark.name == "五竜岳"
                let outbound = distance < route.totalM / 2
                let label = summit ? "五竜岳" : (outbound ? "五竜山荘" : "山荘(復)")
                let labelX = summit ? p.x : p.x + (outbound ? -14 : 14)
                let labelY = summit ? max(5, p.y - 12) : max(16, p.y - 5)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(.white))
                context.draw(Text(label).font(.system(size: 8)).foregroundColor(.white), at: CGPoint(x: labelX, y: labelY))
            }
            func marker(_ distance: Double, color: Color, guide: Bool) {
                guard let altitude = route.position(at: distance).point.altitude else { return }
                let p = project(distance, altitude)
                if guide {
                    var cursor = Path(); cursor.move(to: CGPoint(x: p.x, y: 0)); cursor.addLine(to: CGPoint(x: p.x, y: size.height))
                    context.stroke(cursor, with: .color(color.opacity(0.65)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
                let circle = Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                context.fill(circle, with: .color(color))
                context.stroke(circle, with: .color(.black), lineWidth: 1)
            }
            if let live = display.profileCurrentDistanceM { marker(live, color: .mint, guide: false) }
            if display.isInspecting { marker(display.position.distanceM, color: .orange, guide: true) }
        }
        .accessibilityLabel("経路距離に沿った標高断面。Digital Crownで50メートルずつ先読み")
    }
}

struct RoutePositionSummary: View {
    let route: PlannedRoute
    let display: RouteDisplayContext
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(display.isInspecting ? "先読み" : (display.isOnCourse ? "現在付近" : "計画"))
                    .foregroundStyle(display.isInspecting ? .orange : .mint)
                Text(String(format: "%.2fkm", display.position.distanceM / 1000))
                Spacer(minLength: 0)
                Text(display.position.point.altitude.map { "計画\(Int($0))m" } ?? "計画—m")
            }.font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
            if let next = route.nextLandmark(after: display.position.distanceM) {
                Text("次: \(next.name) · \(Int(max(0, route.landmarkDistance(next) - display.position.distanceM)))m")
                    .font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.secondary)
            } else { Text("コース終点").font(.system(size: 9)).foregroundStyle(.secondary) }
        }
    }
}
