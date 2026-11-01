import SwiftUI

/// One entry per hike, not one per automatically received JSON snapshot.
/// All 85+ raw Watch snapshots and local iPhone histories remain on disk.
struct PhoneHikeHistoryListView: View {
    @ObservedObject var monitor: PhoneHikeMonitor
    @ObservedObject var transfer: RecordTransfer

    @State private var phoneGroups: [HikeHistoryGroup] = []
    @State private var watchGroups: [HikeHistoryGroup] = []
    @State private var selectedHistory: HikeHistoryEntry?
    @State private var pendingWatchImport: RecordExportFile?
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                Text("過去の記録はここから開けます。表示しても現在の登山記録は変更しません。")
                    .font(.footnote)
                Button("記録を再読み込み", systemImage: "arrow.clockwise") { refresh() }
            }

            Section("iPhoneで保存した登山（\(phoneGroups.count)件）") {
                if phoneGroups.isEmpty {
                    Text("iPhoneの記録がまだありません。計測開始後の記録や終了済みの記録が表示されます。")
                        .foregroundStyle(.secondary)
                }
                ForEach(phoneGroups) { group in
                    hikeGroup(group)
                }
            }

            Section {
                Button("Watchから最新の記録を受信", systemImage: "applewatch") {
                    transfer.requestExport()
                }
                Text(transfer.status).font(.footnote).foregroundStyle(.secondary)
                Text("受信したJSON \(transfer.received.count)件 → 登山 \(watchGroups.count)件")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Watchから受信した登山")
            } footer: {
                Text("同じ登山の自動バックアップをまとめて表示します。元のJSONは削除しません。見るだけなら「見る」を押してください。")
            }

            Section("Watchの登山（\(watchGroups.count)件）") {
                if watchGroups.isEmpty {
                    Text("Watchから記録を受信するとここに表示されます。")
                        .foregroundStyle(.secondary)
                }
                ForEach(watchGroups) { group in
                    hikeGroup(group)
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: transfer.received.count) { _, _ in refresh() }
        .onChange(of: monitor.record.state) { _, _ in refresh() }
        .sheet(item: $selectedHistory) { entry in
            NavigationStack {
                PhoneHikeHistoryDetailView(entry: entry)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") { selectedHistory = nil }
                        }
                    }
            }
        }
        .confirmationDialog(
            "Watchの記録でiPhoneの現在の記録を置き換えますか？",
            isPresented: Binding(
                get: { pendingWatchImport != nil },
                set: { if !$0 { pendingWatchImport = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("現在のiPhone記録をバックアップして切り替える") {
                guard let file = pendingWatchImport else { return }
                do {
                    try monitor.importWatchRecord(file)
                    refresh()
                } catch {
                    importError = error.localizedDescription
                }
                pendingWatchImport = nil
            }
            Button("キャンセル", role: .cancel) { pendingWatchImport = nil }
        } message: {
            Text("これは閲覧用ではなく、Watchの記録をiPhoneで続きを計測する操作です。既存のiPhone記録は別ファイルに退避します。Watchで計測中なら一時停止し、最新のバックアップが届いてから行ってください。")
        }
        .alert("記録の引き継ぎに失敗", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("閉じる", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func hikeGroup(_ group: HikeHistoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            recordLine(group.latest, headline: true)
            if !group.older.isEmpty {
                DisclosureGroup("以前のバックアップ \(group.older.count)件") {
                    ForEach(group.older) { earlier in
                        recordLine(earlier, headline: false)
                    }
                }.font(.footnote)
            }
        }
        .padding(.vertical, 5)
    }

    private func recordLine(_ entry: HikeHistoryEntry, headline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(entry.displayedDate, format: .dateTime.year().month().day().hour().minute())
                    .font(headline ? .headline : .subheadline)
                if entry.isCurrentPhone {
                    Text("現在の記録")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Text(String(format: "%.2f km", entry.distance / 1000))
                Text("\(Int(entry.ascent)) m 上昇")
                Text(String(format: "%d:%02d",
                            Int(entry.elapsed)/3600, Int(entry.elapsed)/60%60))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("見る", systemImage: "eye") {
                    selectedHistory = entry
                }
                .buttonStyle(.bordered)
                if entry.source == .phone {
                    ShareLink(item: RawRecordShare(url: entry.url),
                              preview: SharePreview(entry.originalName)) {
                        Label("PCへJSON", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.bordered)
                }
                if entry.source == .watch && headline {
                    Button("iPhoneで続きを計測", systemImage: "arrow.right.circle") {
                        if let raw = transfer.received.first(where: { $0.url == entry.url }) {
                            pendingWatchImport = raw
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(monitor.record.state == .recording)
                }
            }
            .font(.footnote)
        }
    }

    private func refresh() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        phoneGroups = HikeHistoryLibrary.groups(HikeHistoryLibrary.phoneEntries(in: documents))
        watchGroups = HikeHistoryLibrary.groups(HikeHistoryLibrary.watchEntries(from: transfer.received))
    }
}
