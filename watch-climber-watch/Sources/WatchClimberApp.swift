import SwiftUI

@main
struct WatchClimberApp: App {
    @StateObject private var monitor = HikeMonitor()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ClimberView(monitor: monitor)
                .task { monitor.requestLocation() }
                .onChange(of: phase) { _, next in
                    if next == .active { monitor.requestLocation() }
                    else { monitor.persist() }
                }
        }
    }
}

struct ClimberView: View {
    @ObservedObject var monitor: HikeMonitor
    @State private var confirmEnd = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            TabView {
                status(at: timeline.date).tag(0)
                if let terrain = monitor.terrain {
                    TerrainView(terrain: terrain, fix: monitor.fix, now: timeline.date).tag(1)
                } else { Text("地形データを読み込めません").tag(1) }
                track.tag(2)
                controls.tag(3)
            }
            .tabViewStyle(.page)
        }
        .confirmationDialog("記録を終了しますか？", isPresented: $confirmEnd) {
            Button("終了して保存") { Task { await monitor.finish() } }
            Button("キャンセル", role: .cancel) {}
        }
    }
    private func status(at now: Date) -> some View {
        let fresh = monitor.fix.map { now.timeIntervalSince($0.date) < 30 } ?? false
        let altitude = fresh && monitor.fix?.usable == true ? monitor.fix?.altitude : nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text(fresh ? monitor.locationMessage : "GPS位置更新待ち").font(.caption2).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(altitude.map { String(Int($0)) } ?? "—").font(.system(size: 38, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                    Text("m").foregroundStyle(.secondary)
                }
                Text("GPS標高").font(.caption2)
                HStack {
                    metric("上昇", "\(Int(monitor.record.ascent))m")
                    Spacer()
                    metric("心拍", monitor.currentHeartRate(at: now).map { "\(Int($0))" } ?? "—")
                }
                HStack {
                    metric("時間", String(format: "%d:%02d", Int(monitor.record.elapsed)/3600, Int(monitor.record.elapsed)/60%60))
                    Spacer()
                    metric("距離", String(format: "%.2fkm", monitor.record.distance/1000))
                }
                if let fix = monitor.fix {
                    Text(String(format: "%.5f, %.5f", fix.latitude, fix.longitude)).font(.system(size: 10, design: .monospaced))
                    Text(fix.accuracy >= 0 ? "精度 ±\(Int(fix.accuracy))m · \(max(0, Int(now.timeIntervalSince(fix.date))))秒前" : "精度未取得").font(.caption2).foregroundStyle(.secondary)
                }
                if let error = monitor.saveMessage { Text(error).foregroundStyle(.orange).font(.caption2) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).monospacedDigit())
        }
    }
    private var track: some View {
        VStack {
            Text("記録した軌跡").font(.caption)
            Canvas { context, size in
                let points = monitor.record.points
                guard let first = points.first else { return }
                let cosLat = cos(first.fix.latitude * .pi/180)
                let xs = points.map { ($0.fix.longitude-first.fix.longitude)*cosLat }
                let ys = points.map { first.fix.latitude-$0.fix.latitude }
                let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
                let span = max(maxX-minX, maxY-minY, 0.0001)
                let scale = Double(min(size.width, size.height)-20)/span
                var path = Path()
                for (index, point) in points.enumerated() {
                    let p = CGPoint(x: Double(size.width)/2+(xs[index]-(minX+maxX)/2)*scale,
                                    y: Double(size.height)/2+(ys[index]-(minY+maxY)/2)*scale)
                    if point.breakBefore || index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    if index == points.count-1 { context.fill(Path(ellipseIn: CGRect(x:p.x-3,y:p.y-3,width:6,height:6)), with: .color(.white)) }
                }
                context.stroke(path, with: .color(.mint), lineWidth: 2)
            }
            Text(monitor.record.points.isEmpty ? "開始するとGPSの軌跡を記録" : "北が上 · 背景地図なし").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var controls: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(stateLabel).font(.headline)
                switch monitor.record.state {
                case .idle, .finished:
                    Button(monitor.starting ? "開始中…" : "記録開始") { Task { await monitor.start() } }
                        .tint(.mint).disabled(monitor.record.state == .finished && monitor.saveMessage != nil)
                case .recording:
                    Button("一時停止") { monitor.pause() }
                    Button("終了") { confirmEnd = true }
                case .paused:
                    Button("再開") { Task { await monitor.resume() } }.tint(.mint)
                    Button("終了") { confirmEnd = true }
                }
                if let message = monitor.workoutMessage { Text(message).font(.caption2).foregroundStyle(.orange) }
                if let message = monitor.saveMessage {
                    Text(message).font(.caption2).foregroundStyle(.orange)
                    Button("保存を再試行") { monitor.persist() }
                }
            }.disabled(monitor.starting || monitor.finishing)
        }
    }
    private var stateLabel: String {
        if monitor.finishing { return "保存中…" }
        switch monitor.record.state {
        case .idle: return "未開始"
        case .recording: return "記録中"
        case .paused: return "一時停止"
        case .finished: return "記録終了"
        }
    }
}
