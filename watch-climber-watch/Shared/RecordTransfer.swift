import Foundation
import Combine
import WatchConnectivity

final class RecordTransfer: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "WatchとiPhoneのアプリを開いてください"
    @Published private(set) var received: [RecordExportFile] = []
    @Published private(set) var routeSyncStatus = "GPXを取り込むとWatchに送信します"
    @Published private(set) var liveHeartRate: Double?
    @Published private(set) var liveHeartDate: Date?

    func currentHeartRate(at date: Date) -> Double? {
        guard let bpm = liveHeartRate, let measured = liveHeartDate,
              date.timeIntervalSince(measured) >= -5,
              date.timeIntervalSince(measured) < 30 else { return nil }
        return bpm
    }

    /// Watch sensor is the live source; iPhone never claims to have a heart-rate sensor.
    func publishHeartRate(_ bpm: Double?, at date: Date = Date()) {
        #if os(watchOS)
        guard let session, session.activationState == .activated,
              let bpm, bpm.isFinite, bpm >= 25, bpm <= 250 else { return }
        let value: [String: Any] = ["kind": "live-heart", "bpm": bpm,
                                    "measuredAt": date.timeIntervalSince1970]
        if session.isReachable { session.sendMessage(value, replyHandler: nil, errorHandler: nil) }
        try? session.updateApplicationContext(value)
        #endif
    }

    private func receiveHeartRate(_ message: [String: Any]) {
        #if os(iOS)
        guard message["kind"] as? String == "live-heart",
              let bpm = message["bpm"] as? Double, bpm.isFinite, bpm >= 25, bpm <= 250,
              let epoch = message["measuredAt"] as? Double, epoch.isFinite else { return }
        let date = Date(timeIntervalSince1970: epoch)
        guard abs(date.timeIntervalSinceNow) < 60,
              date > (liveHeartDate ?? .distantPast) else { return }
        liveHeartRate = bpm
        liveHeartDate = date
        #endif
    }
    private let documents: URL
    private let store: RecordExportStore
    private var session: WCSession?
    private var requestWhenActivated = false
    private var expectedIDs = Set<String>()
    private var confirmedIDs = Set<String>()
    private var expectedReceipts = Set<String>()
    private var lastAutomaticSnapshot = Date.distantPast

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


    /// Only the newest current snapshot is queued automatically, at most once
    /// every two minutes. This allows a phone fallback when the Watch battery
    /// runs out, without claiming to be an always-current mirror.
    func autoSyncCurrentRecord() {
        #if os(watchOS)
        guard Date().timeIntervalSince(lastAutomaticSnapshot) >= 120,
              let session, session.activationState == .activated,
              session.isCompanionAppInstalled,
              session.outstandingFileTransfers.count < 4 else { return }
        do {
            let files = try store.snapshotRecords(in: documents)
            guard let current = files.first(where: { $0.originalName == "current-hike.json" }) else { return }
            var metadata = current.metadata
            metadata["requestID"] = UUID().uuidString
            session.transferFile(current.url, metadata: metadata)
            lastAutomaticSnapshot = Date()
        } catch {
            status = "自動バックアップの準備に失敗: \(error.localizedDescription)"
        }
        #endif
    }

    func sendHannoRoute() throws {
        #if os(iOS)
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else {
            routeSyncStatus = "Watchアプリとの接続を確認してください"
            return
        }
        let url = ImportedRouteStore.destination()
        let bytes = try Data(contentsOf: url)
        _ = try ImportedRouteStore.validate(bytes)
        session.transferFile(url, metadata: ["kind": "hanno-route",
                                             "sha256": RecordExportFile.digest(bytes)])
        routeSyncStatus = "ルートをWatchへ転送待ちです"
        #endif
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
            #if os(iOS)
            switch userInfo["kind"] as? String {
            case "hanno-route-saved": self.routeSyncStatus = "Watchにもルートを保存しました"
            case "hanno-route-failed": self.routeSyncStatus = "Watchでルート保存に失敗しました。再送してください"
            default: break
            }
            #endif
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if os(watchOS)
        guard file.metadata?["kind"] as? String == "hanno-route" else { return }
        do {
            let bytes = try Data(contentsOf: file.fileURL)
            guard let expected = file.metadata?["sha256"] as? String,
                  RecordExportFile.digest(bytes) == expected else {
                throw RecordExportError.integrityMismatch
            }
            try ImportedRouteStore.save(bytes)
            session.transferUserInfo(["kind": "hanno-route-saved"])
        } catch {
            session.transferUserInfo(["kind": "hanno-route-failed"])
            DispatchQueue.main.async {
                self.status = "ルート保存失敗: \(error.localizedDescription)"
            }
        }
        #else
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
        #endif
    }


    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { self.receiveHeartRate(message) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.receiveHeartRate(applicationContext) }
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
