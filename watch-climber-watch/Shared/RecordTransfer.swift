import Foundation
import Combine
import WatchConnectivity

final class RecordTransfer: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "WatchとiPhoneのアプリを開いてください"
    @Published private(set) var received: [RecordExportFile] = []
    private let documents: URL
    private let store: RecordExportStore
    private var session: WCSession?
    private var requestWhenActivated = false
    private var expectedIDs = Set<String>()
    private var confirmedIDs = Set<String>()
    private var expectedReceipts = Set<String>()

    override init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        documents = directory
        #if os(watchOS)
        store = RecordExportStore(directory: directory.appendingPathComponent("RecordExports"))
        #else
        store = RecordExportStore(directory: directory.appendingPathComponent("WatchRecords"))
        #endif
        super.init()
        refreshReceived()
        guard WCSession.isSupported() else { status = "この端末はWatchとの転送に対応していません"; return }
        session = .default
        session?.delegate = self
        session?.activate()
    }

    /// UI entry point, always called on the main thread.
    func requestExport() {
        guard let session else { return }
        guard session.activationState == .activated else {
            requestWhenActivated = true
            status = "接続準備中…"
            session.activate()
            return
        }
        #if os(watchOS)
        queueRecords(session)
        #else
        guard session.isPaired, session.isWatchAppInstalled else {
            status = "ペアリングしたWatchにWatch Climberをインストールしてください"
            return
        }
        session.transferUserInfo(["kind": "export-request", "requestID": UUID().uuidString])
        status = "取り出しを依頼しました。Watchのアプリも開いてお待ちください"
        #endif
    }

    @discardableResult
    private func refreshReceived() -> Bool {
        #if os(iOS)
        do { received = try store.files(); return true }
        catch { status = "保存済みファイルの確認失敗: \(error.localizedDescription)。ファイルアプリのWatch Climberも確認してください"; return false }
        #else
        return true
        #endif
    }

    #if os(watchOS)
    private func queueRecords(_ session: WCSession) {
        guard session.isCompanionAppInstalled else {
            status = "iPhoneにもWatch Climberをインストールして開いてください"
            return
        }
        do {
            let files = try store.snapshotRecords(in: documents)
            expectedIDs = Set(files.map(\.id))
            confirmedIDs = []
            expectedReceipts = []
            var pending: [String: String] = [:]
            for transfer in session.outstandingFileTransfers {
                guard let metadata = transfer.file.metadata,
                      let name = metadata["originalName"] as? String,
                      let digest = metadata["sha256"] as? String,
                      let requestID = metadata["requestID"] as? String else { continue }
                pending["\(name)--\(digest)"] = requestID
            }
            for file in files {
                let requestID = pending[file.id] ?? UUID().uuidString
                expectedReceipts.insert("\(file.id)|\(requestID)")
                if pending[file.id] == nil {
                    var metadata = file.metadata
                    metadata["requestID"] = requestID
                    session.transferFile(file.url, metadata: metadata)
                }
            }
            status = files.isEmpty ? "取り出せる記録はありません" : "\(files.count)件を転送待ち。iPhoneの保存確認を待っています"
        } catch { status = "取り出し準備失敗: \(error.localizedDescription)" }
    }
    #endif

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error { self.status = "接続失敗: \(error.localizedDescription)"; return }
            if activationState == .activated, self.requestWhenActivated {
                self.requestWhenActivated = false
                self.requestExport()
            }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            #if os(watchOS)
            switch userInfo["kind"] as? String {
            case "export-request": self.requestExport()
            case "saved-receipt":
                guard let id = userInfo["id"] as? String,
                      let requestID = userInfo["requestID"] as? String,
                      self.expectedReceipts.contains("\(id)|\(requestID)") else { return }
                self.confirmedIDs.insert(id)
                self.status = "iPhone保存確認 \(self.confirmedIDs.count)/\(self.expectedIDs.count)件。Watchの原本は残っています"
            case "receive-failed": self.status = "iPhoneの保存に失敗しました。もう一度送ってください"
            default: break
            }
            #endif
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if os(iOS)
        do {
            // MUST stay synchronous: WCSession deletes this temporary file after return.
            guard let metadata = file.metadata, let requestID = metadata["requestID"] as? String,
                  UUID(uuidString: requestID) != nil else { throw RecordExportError.invalidFile }
            let saved = try store.receive(temporaryURL: file.fileURL, metadata: metadata)
            session.transferUserInfo(["kind": "saved-receipt", "id": saved.id, "requestID": requestID])
            DispatchQueue.main.async {
                if self.refreshReceived() {
                    self.status = "\(self.received.count)件をiPhoneに保存済み。各ファイルから共有できます"
                }
            }
        } catch {
            session.transferUserInfo(["kind": "receive-failed"])
            DispatchQueue.main.async { self.status = "受信・保存失敗: \(error.localizedDescription)。もう一度取り出してください" }
        }
        #endif
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let error else { return } // Delivery alone is not a durable receipt.
        DispatchQueue.main.async { self.status = "転送失敗: \(error.localizedDescription)。もう一度送ってください" }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
