import SwiftUI

/// A read-only viewer. Opening a past hike NEVER changes the active phone hike.
struct PhoneHikeHistoryDetailView: View {
    let entry: HikeHistoryEntry

    @State private var record: HikeRecord?
    @State private var terrain: Terrain?
    @State private var errorMessage: String?
    @State private var exportedFiles: [String: URL] = [:]
    @State private var exportError: String?
    @State private var selectedIndex = 0
    @State private var selectedPage: Page = .track

    private enum Page: String, CaseIterable, Identifiable {
        case track = "軌跡"
        case elevation = "標高"
        case terrain = "3D地形"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let record {
                    Text(entry.source == .phone ? "iPhoneに保存された登山記録" : "Watchから受信した登山記録")
                        .font(.headline)
                    Text(entry.displayedDate, format: .dateTime.year().month().day().hour().minute())
                        .font(.subheadline).foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        metric("距離", String(format: "%.2f km", record.distance / 1000))
                        metric("累積上昇", "\(Int(record.ascent)) m")
                        metric("計測時間", String(format: "%d:%02d",
                                                Int(record.elapsed)/3600, Int(record.elapsed)/60%60))
                    }
                    Text("\(record.points.count)件のGPS地点 · 元データは変更しません")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("表示", selection: $selectedPage) {
                        ForEach(Page.allCases) { page in
                            Text(page.rawValue).tag(page)
                        }
                    }.pickerStyle(.segmented)

                    switch selectedPage {
                    case .track:
                        recordedTrack(record)
                    case .elevation:
                        recordedElevation(record)
                    case .terrain:
                        if let terrain {
                            PhoneTerrainView(terrain: terrain, route: nil, display: nil,
                                             fix: nil, inspection: .constant(RouteInspection()),
                                             archivedPoints: record.points,
                                             replayFix: point(at: selectedIndex, in: record)?.fix)
                            replayControl(record)
                        } else {
                            Text("この記録に対応する3D標高データがありません。GPS軌跡と標高履歴は確認できます。")
                                .font(.footnote).foregroundStyle(.secondary)
                            recordedTrack(record)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("PCで可視化・解析").font(.headline)
                        Text("JSONはWatch ClimberのPC用3Dビューアにそのまま読み込めます。GPXは地図アプリ、CSVは表計算・解析、GeoJSONはGIS向けです。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ShareLink(item: RawRecordShare(url: entry.url),
                                  preview: SharePreview(entry.originalName)) {
                            Label("PCへ送る：元のJSON", systemImage: "square.and.arrow.up")
                        }.buttonStyle(.borderedProminent)

                        if let url = exportedFiles["gpx"] {
                            ShareLink(item: GPXRecordShare(url: url),
                                      preview: SharePreview(url.lastPathComponent)) {
                                Label("GPXを共有", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            }.buttonStyle(.bordered)
                        }
                        if let url = exportedFiles["csv"] {
                            ShareLink(item: CSVRecordShare(url: url),
                                      preview: SharePreview(url.lastPathComponent)) {
                                Label("CSVを共有", systemImage: "tablecells")
                            }.buttonStyle(.bordered)
                        }
                        if let url = exportedFiles["geojson"] {
                            ShareLink(item: GeoJSONRecordShare(url: url),
                                      preview: SharePreview(url.lastPathComponent)) {
                                Label("GeoJSONを共有", systemImage: "globe")
                            }.buttonStyle(.bordered)
                        }
                        if let exportError {
                            Text("GPX/CSV出力に失敗: \(exportError)")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let errorMessage {
                    ContentUnavailableView("記録を開けません", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else {
                    ProgressView("記録を読み込み中")
                }
            }
            .padding()
        }
        .navigationTitle("登山の記録")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entry.id) {
            do {
                let result = try HikeHistoryLibrary.read(entry)
                record = result
                selectedIndex = max(0, result.points.count-1)
                do {
                    let documents = FileManager.default.urls(for: .documentDirectory,
                                                              in: .userDomainMask)[0]
                    exportedFiles = try HikeRecordExports.save(result, under: documents)
                    exportError = nil
                } catch {
                    exportedFiles = [:]
                    exportError = error.localizedDescription
                }
                let options = [Terrain.load(named: "hanno"), Terrain.load(named: "goryu"), Terrain.load(named: "amagi")].compactMap { $0 }
                terrain = result.points.first.flatMap { first in
                    options.first { $0.grid(latitude: first.fix.latitude,
                                            longitude: first.fix.longitude) != nil }
                }
                errorMessage = nil
            } catch {
                record = nil
                errorMessage = "ファイルが変更されたか破損しています。元データはそのまま残しています: \(error.localizedDescription)"
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func point(at index: Int, in record: HikeRecord) -> HikeRecord.Point? {
        guard !record.points.isEmpty else { return nil }
        return record.points[min(max(0,index),record.points.count-1)]
    }

    private func replayControl(_ record: HikeRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("過去の軌跡を再生・確認")
                .font(.caption).foregroundStyle(.secondary)
            if let selected = point(at: selectedIndex, in: record) {
                Text(selected.fix.date, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
            }
            if record.points.count > 1 {
                Slider(value: Binding(
                    get: { Double(selectedIndex) },
                    set: { selectedIndex = Int($0.rounded()) }
                ), in: 0...Double(record.points.count-1), step: 1)
                .accessibilityLabel("登山軌跡を前後に移動")
            }
        }
    }

    private func recordedTrack(_ hike: HikeRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("実測GPS軌跡（北が上、背景地図なし）").font(.subheadline)
            Canvas { context, size in
                let points = hike.points
                guard let first = points.first else { return }
                let scaleLongitude = cos(first.fix.latitude * .pi / 180)
                let xs = points.map { ($0.fix.longitude - first.fix.longitude) * scaleLongitude }
                let ys = points.map { first.fix.latitude - $0.fix.latitude }
                guard let minX = xs.min(), let maxX = xs.max(),
                      let minY = ys.min(), let maxY = ys.max() else { return }
                let span = max(maxX-minX, maxY-minY, 0.000001)
                let scale = Double(max(1, min(size.width, size.height) - 28)) / span
                var path = Path()
                for (index, point) in points.enumerated() {
                    let p = CGPoint(x: Double(size.width)/2 +
                                         (xs[index] - (minX+maxX)/2)*scale,
                                    y: Double(size.height)/2 +
                                         (ys[index] - (minY+maxY)/2)*scale)
                    if index == 0 || point.breakBefore { path.move(to: p) }
                    else { path.addLine(to: p) }
                }
                context.stroke(path, with: .color(.mint), lineWidth: 2.5)
                let at = min(max(selectedIndex, 0), max(0, points.count-1))
                let p = CGPoint(x: Double(size.width)/2+(xs[at]-(minX+maxX)/2)*scale,
                                y: Double(size.height)/2+(ys[at]-(minY+maxY)/2)*scale)
                context.fill(Path(ellipseIn: CGRect(x: p.x-5, y: p.y-5, width: 10, height: 10)),
                             with: .color(.orange))
            }
            .frame(height: 320)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("緑：実際の軌跡　橙：選択中の地点。GPSが途切れた区間は結びません。")
                .font(.footnote).foregroundStyle(.secondary)
            replayControl(hike)
        }
    }

    private func recordedElevation(_ hike: HikeRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("記録されたGPS標高").font(.subheadline)
            let heights = hike.points.compactMap { $0.fix.altitude }
            if heights.count < 2 {
                Text("標高データが2点以上ありません。")
                    .foregroundStyle(.secondary)
            } else {
                Canvas { context, size in
                    guard let low = heights.min(), let high = heights.max(),
                          let start = hike.points.first?.fix.date.timeIntervalSince1970,
                          let end = hike.points.last?.fix.date.timeIntervalSince1970 else { return }
                    let duration = max(1, end-start)
                    let span = max(1, high-low)
                    let graphHeight = max(20, Double(size.height)-34)
                    var path = Path(), connected = false
                    for p in hike.points {
                        guard let height = p.fix.altitude else {
                            connected = false
                            continue
                        }
                        let x = (p.fix.date.timeIntervalSince1970-start)/duration*Double(size.width)
                        let y = 18+(high-height)/span*graphHeight
                        let point = CGPoint(x: x, y: y)
                        if p.breakBefore || !connected { path.move(to: point) }
                        else { path.addLine(to: point) }
                        connected = true
                    }
                    context.stroke(path, with: .color(.mint), lineWidth: 2)
                    context.draw(Text("\(Int(high)) m").font(.caption2).foregroundColor(.white),
                                 at: CGPoint(x: 28, y: 9))
                    context.draw(Text("\(Int(low)) m").font(.caption2).foregroundColor(.white),
                                 at: CGPoint(x: 28, y: size.height-10))
                    if let current = point(at: selectedIndex, in: hike),
                       let height = current.fix.altitude {
                        let x = (current.fix.date.timeIntervalSince1970-start)/duration*Double(size.width)
                        let y = 18+(high-height)/span*graphHeight
                        context.fill(Path(ellipseIn: CGRect(x: x-5,y: y-5,width: 10,height: 10)),
                                     with: .color(.orange))
                    }
                }
                .frame(height: 240)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                replayControl(hike)
            }
        }
    }
}
