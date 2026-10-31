import SwiftUI
import UniformTypeIdentifiers

/// Share the original, verified JSON bytes; never re-encode a received record.
struct RawRecordShare: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { value in
            SentTransferredFile(value.url)
        }
    }
}

@main
struct WatchClimberPhoneApp: App {
    @StateObject private var transfer = RecordTransfer()
    @StateObject private var monitor = PhoneHikeMonitor()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            PhoneClimberView(monitor: monitor, transfer: transfer)
                .task { monitor.requestLocation() }
                .onChange(of: phase) { _, next in
                    if next == .active { monitor.requestLocation() }
                    else { monitor.persist() }
                }
        }
    }
}

private enum PhoneTab: Hashable { case hike, terrain, profile, track, watchRecords }

struct PhoneClimberView: View {
    @ObservedObject var monitor: PhoneHikeMonitor
    @ObservedObject var transfer: RecordTransfer
    @State private var tab: PhoneTab = .hike
    @State private var inspection = RouteInspection()
    @State private var confirmEnd = false
    @State private var importFile: RecordExportFile?
    @State private var importError: String?
    @State private var showGPXImporter = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { dashboard.navigationTitle("登山")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { mountainMenu } } }
                .tabItem { Label("状況", systemImage: "figure.hiking") }.tag(PhoneTab.hike)
            NavigationStack { terrainPage.navigationTitle("3D地形")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { mountainMenu } } }
                .tabItem { Label("地形", systemImage: "mountain.2") }.tag(PhoneTab.terrain)
            NavigationStack { profilePage.navigationTitle("標高断面")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { mountainMenu } } }
                .tabItem { Label("断面", systemImage: "chart.xyaxis.line") }.tag(PhoneTab.profile)
            NavigationStack { trackPage.navigationTitle("軌跡") }
                .tabItem { Label("軌跡", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }.tag(PhoneTab.track)
            NavigationStack { watchRecords.navigationTitle("Watchの記録") }
                .tabItem { Label("Watch記録", systemImage: "applewatch") }.tag(PhoneTab.watchRecords)
        }
        .confirmationDialog("iPhoneで記録を終了しますか？", isPresented: $confirmEnd) {
            Button("終了して保存") { monitor.finish() }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("Watchの記録をiPhoneに引き継ぎますか？",
                            isPresented: Binding(get: { importFile != nil }, set: { if !$0 { importFile = nil } })) {
            Button("引き継ぐ") {
                guard let selected = importFile else { return }
                do {
                    try monitor.importWatchRecord(selected)
                    tab = .hike
                } catch {
                    importError = error.localizedDescription
                }
                importFile = nil
            }
            Button("キャンセル", role: .cancel) { importFile = nil }
        } message: {
            Text("まずWatchで記録を一時停止し、最新のJSONがiPhoneに保存されたことを確認してください。未転送分は引き継げません。")
        }
        .fileImporter(isPresented: $showGPXImporter,
                      allowedContentTypes: [.xml, .data, UTType(filenameExtension: "gpx") ?? .xml]) { result in
            do {
                let url = try result.get()
                let scope = url.startAccessingSecurityScopedResource()
                defer { if scope { url.stopAccessingSecurityScopedResource() } }
                let bytes = try Data(contentsOf: url)
                try monitor.importGPX(bytes)
                try transfer.sendHannoRoute()
                tab = .profile
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("取り込み失敗", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("閉じる", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private func changeMountain(_ selection: MountainSelection) {
        monitor.chooseMountain(selection)
        inspection.followGPS()
    }

    private var mountainMenu: some View {
        Menu {
            ForEach(MountainSelection.allCases) { selection in
                Button {
                    changeMountain(selection)
                } label: {
                    if monitor.mountainSelection == selection {
                        Label(selection.title, systemImage: "checkmark")
                    } else {
                        Text(selection.title)
                    }
                }
            }
        } label: {
            Label("山を切り替え", systemImage: "mountain.2")
        }
    }

    private var dashboard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let age = monitor.fix.map { timeline.date.timeIntervalSince($0.date) }
            let fresh = age.map { $0 >= -5 && $0 < 30 } ?? false
            let altitude = fresh && monitor.fix?.usable == true ? monitor.fix?.altitude : nil
            List {
                Section("表示する山") {
                    Picker("山", selection: Binding(
                        get: { monitor.mountainSelection },
                        set: { changeMountain($0) }
                    )) {
                        ForEach(MountainSelection.allCases) { selection in
                            Text(selection.title).tag(selection)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("選択中: \(monitor.terrain?.name ?? "地形なし")")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("山の切り替えは地形と予定ルートの表示のみ変更し、登山記録は変更しません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("GPS標高") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(altitude.map { String(Int($0)) } ?? "—")
                            .font(.system(size: 55, weight: .semibold, design: .rounded))
                        Text("m").foregroundStyle(.secondary)
                    }
                    Text(fresh ? monitor.locationStatus : "GPS更新待ち")
                        .foregroundStyle(.secondary)
                    if let fix = monitor.fix {
                        Text(String(format: "%.5f, %.5f  ·  精度 ±%.0fm",
                                    fix.latitude, fix.longitude, fix.accuracy))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Section("登山記録") {
                    LabeledContent("累積上昇", value: "\(Int(monitor.record.ascent)) m")
                    LabeledContent("距離", value: String(format: "%.2f km", monitor.record.distance / 1000))
                    LabeledContent("時間", value: String(format: "%d:%02d",
                        Int(monitor.record.elapsed)/3600, Int(monitor.record.elapsed)/60%60))
                    LabeledContent("心拍", value: transfer.currentHeartRate(at: timeline.date).map {
                        "\(Int($0)) bpm"
                    } ?? "—")
                    if transfer.currentHeartRate(at: timeline.date) == nil {
                        Text("心拍はApple Watchから受信。30秒以上更新がない場合は非表示")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("操作") {
                    Text(stateText).font(.headline)
                    switch monitor.record.state {
                    case .idle, .finished:
                        Button("記録開始", systemImage: "play.fill") { monitor.startOrResume() }
                            .disabled(monitor.saveError != nil)
                    case .paused:
                        Button("記録再開", systemImage: "play.fill") { monitor.startOrResume() }
                        Button("記録終了", systemImage: "stop.fill") { confirmEnd = true }
                    case .recording:
                        Button("一時停止", systemImage: "pause.fill") { monitor.pause() }
                        Button("記録終了", systemImage: "stop.fill") { confirmEnd = true }
                    }
                    if let message = monitor.infoMessage { Text(message).font(.footnote) }
                    if let error = monitor.saveError {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                        Button("保存を再試行") { monitor.persist() }
                    }
                }
                Section("予定ルート") {
                    Button("GPXファイルを取り込む", systemImage: "square.and.arrow.down") {
                        showGPXImporter = true
                    }
                    Text(monitor.route?.name ?? "正確なルートのGPX未登録")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(transfer.routeSyncStatus)
                        .font(.footnote).foregroundStyle(.secondary)
                    if ImportedRouteStore.load() != nil {
                        Button("WatchへGPXを再送", systemImage: "arrow.clockwise") {
                            do { try transfer.sendHannoRoute() }
                            catch { importError = error.localizedDescription }
                        }
                    }
                }
                Section("記録ファイル") {
                    if let url = monitor.savedFile {
                        ShareLink(item: RawRecordShare(url: url),
                                  preview: SharePreview("iPhone登山記録.json")) {
                            Label("iPhoneの記録を共有・保存", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Text("記録開始後にファイルを書き出せます").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("記録中はiPhoneの位置情報をバックグラウンドでも更新します。Watchと二重に記録する場合は距離が合算されません。切替時はWatchを一時停止してください。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var stateText: String {
        switch monitor.record.state {
        case .idle: return "未開始"
        case .recording: return "記録中"
        case .paused: return "一時停止"
        case .finished: return "記録終了"
        }
    }


    private var terrainPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Group {
                if let terrain = monitor.terrain {
                    let display = monitor.route.map {
                        RouteDisplayContext(route: $0, fix: monitor.fix,
                                            now: timeline.date,
                                            progressHintM: monitor.record.distance,
                                            inspection: inspection)
                    }
                    PhoneTerrainView(terrain: terrain, route: monitor.route,
                                     display: display, fix: monitor.fix, inspection: $inspection)
                } else {
                    ContentUnavailableView("地形データなし", systemImage: "mountain.2",
                                           description: Text("DEMを読み込めません"))
                }
            }
        }
    }

    private var profilePage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let display = monitor.route.map {
                RouteDisplayContext(route: $0, fix: monitor.fix,
                                    now: timeline.date,
                                    progressHintM: monitor.record.distance,
                                    inspection: inspection)
            }
            PhoneElevationProfileView(route: monitor.route, display: display,
                                      record: monitor.record, terrain: monitor.terrain,
                                      inspection: $inspection)
        }
    }

    private var trackPage: some View {
        VStack(spacing: 12) {
            Text("実際に記録したGPS軌跡 · 北が上").font(.subheadline)
            Canvas { context, size in
                let points = monitor.record.points
                guard let first = points.first else { return }
                let latScale = cos(first.fix.latitude * .pi / 180)
                let xs = points.map { ($0.fix.longitude - first.fix.longitude) * latScale }
                let ys = points.map { first.fix.latitude - $0.fix.latitude }
                guard let xMin = xs.min(), let xMax = xs.max(),
                      let yMin = ys.min(), let yMax = ys.max() else { return }
                let span = max(xMax - xMin, yMax - yMin, 0.0001)
                let scale = max(1, Double(min(size.width, size.height) - 30)) / span
                var path = Path()
                for (index, point) in points.enumerated() {
                    let p = CGPoint(x: Double(size.width)/2+(xs[index] - (xMin + xMax)/2)*scale,
                                    y: Double(size.height)/2+(ys[index] - (yMin + yMax)/2)*scale)
                    if index == 0 || point.breakBefore { path.move(to: p) }
                    else { path.addLine(to: p) }
                    if index == points.count - 1 {
                        context.fill(Path(ellipseIn: CGRect(x: p.x-5, y: p.y-5, width: 10, height: 10)), with: .color(.mint))
                    }
                }
                context.stroke(path, with: .color(.mint), lineWidth: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Text("\(monitor.record.points.count) GPS地点 · 背景地図・ナビゲーションなし")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding()
    }

    private var watchRecords: some View {
        List {
            Section {
                Button("Watchから取り出す", systemImage: "applewatch") { transfer.requestExport() }
                Text(transfer.status).font(.footnote)
            } footer: {
                Text("WatchとiPhoneの両方でアプリを開いてください。原本はWatchに残ります。")
            }
            Section("受信した記録（\(transfer.received.count)件）") {
                ForEach(transfer.received) { file in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(file.originalName).font(.subheadline).textSelection(.enabled)
                        if let date = (try? file.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                            Text(date, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(file.byteCount) bytes · SHA-256 \(file.sha256.prefix(12))…")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            ShareLink(item: RawRecordShare(url: file.url),
                                      preview: SharePreview(file.originalName)) {
                                Label("共有・保存", systemImage: "square.and.arrow.up")
                            }
                            Spacer()
                            Button("引き継ぐ") { importFile = file }
                                .disabled(monitor.record.state == .recording)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
    }
}
