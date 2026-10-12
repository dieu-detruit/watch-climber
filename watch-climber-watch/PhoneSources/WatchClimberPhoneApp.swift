import SwiftUI
import UniformTypeIdentifiers

/// Export as a real file attachment, without parsing or rewriting the payload.
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
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section {
                        Button("Watchから取り出す", systemImage: "applewatch") { transfer.requestExport() }
                        Text(transfer.status).font(.footnote)
                    } footer: {
                        Text("WatchとiPhoneを近くに置き、両方のアプリを開いてください。記録は元のJSONのままコピーし、Watchから削除しません。転送に時間がかかることがあります。")
                    }
                    Section("受信した記録（\(transfer.received.count)件）") {
                        ForEach(transfer.received) { file in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(file.originalName).font(.subheadline).textSelection(.enabled)
                                Text("\(file.byteCount) bytes · SHA-256 \(file.sha256.prefix(12))…")
                                    .font(.caption).foregroundStyle(.secondary)
                                ShareLink(item: RawRecordShare(url: file.url), preview: SharePreview(file.originalName)) { Label("共有・ファイルに保存", systemImage: "square.and.arrow.up") }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                .navigationTitle("Watchの記録")
            }
        }
    }
}
