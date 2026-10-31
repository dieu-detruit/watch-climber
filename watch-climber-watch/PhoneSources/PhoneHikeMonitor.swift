import SwiftUI
import CoreLocation

/// Independent iPhone recorder. It never modifies raw Watch backups.
@MainActor
final class PhoneHikeMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var fix: Fix?
    @Published private(set) var record = HikeRecord()
    @Published private(set) var terrain: Terrain? = Terrain.load(named: "hanno") ?? Terrain.load()
    private lazy var terrainOptions = [Terrain.load(named: "hanno"), Terrain.load()].compactMap { $0 }
    @Published private(set) var locationStatus = "位置情報を確認中"
    @Published private(set) var saveError: String?
    @Published private(set) var infoMessage: String?
    private let location = CLLocationManager()
    private let directory: URL
    private let currentURL: URL
    private var ticker: Timer?
    private var lastSaved = Date.distantPast
    private var canWrite = true

    override convenience init() {
        self.init(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }

    init(directory: URL) {
        self.directory = directory
        currentURL = directory.appendingPathComponent("current-phone-hike.json")
        super.init()
        // An unreadable previous record is never overwritten on this launch.
        if FileManager.default.fileExists(atPath: currentURL.path) {
            do {
                record = try JSONDecoder().decode(HikeRecord.self, from: Data(contentsOf: currentURL))
                record.prepareAfterRestore()
            } catch {
                canWrite = false
                saveError = "既存のiPhone記録を読み込めません。ファイルを保護するため書き込みを停止しました"
            }
        }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
        location.activityType = .fitness
        location.pausesLocationUpdatesAutomatically = false
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.record.state == .recording else { return }
                self.record.advanceTime(to: Date())
                if Date().timeIntervalSince(self.lastSaved) >= 10 { self.persist() }
            }
        }
    }

    func requestLocation() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: location.startUpdatingLocation()
        case .restricted, .denied: locationStatus = "設定で位置情報を許可してください"
        @unknown default: locationStatus = "位置情報の権限を確認してください"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for value in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                guard abs(value.timestamp.timeIntervalSinceNow) < 30,
                      self.fix == nil || value.timestamp > self.fix!.date else { continue }
                let next = Fix(date: value.timestamp,
                               latitude: value.coordinate.latitude,
                               longitude: value.coordinate.longitude,
                               altitude: value.verticalAccuracy >= 0 && value.verticalAccuracy <= 50 ? value.altitude : nil,
                               accuracy: value.horizontalAccuracy)
                self.fix = next
                if next.usable,
                   let selected = self.terrainOptions.first(where: {
                       $0.grid(latitude: next.latitude, longitude: next.longitude) != nil
                   }), selected.name != self.terrain?.name {
                    self.terrain = selected
                }
                self.locationStatus = next.usable ? "GPS" : "GPS精度不足"
                self.record.ingest(next)
            }
            if self.record.state == .recording && Date().timeIntervalSince(self.lastSaved) >= 10 {
                self.persist()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationStatus = "位置を取得できません"
            self.record.breakTrack()
        }
    }

    func startOrResume() {
        guard canWrite else { return }
        guard location.authorizationStatus == .authorizedAlways ||
              location.authorizationStatus == .authorizedWhenInUse else {
            requestLocation()
            infoMessage = "位置情報を許可してから記録開始してください"
            return
        }
        guard record.state != .recording else { return }
        if record.state == .finished || record.state == .idle { record = HikeRecord() }
        record.resume()
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = true
        location.startUpdatingLocation()
        infoMessage = nil
        persist()
    }

    func pause() {
        guard record.state == .recording else { return }
        record.advanceTime(to: Date())
        record.pause()
        location.allowsBackgroundLocationUpdates = false
        persist()
    }

    func finish() {
        guard record.state == .recording || record.state == .paused else { return }
        if record.state == .recording { record.advanceTime(to: Date()) }
        record.pause()
        record.state = .finished
        location.allowsBackgroundLocationUpdates = false
        persist()
    }

    func persist() {
        guard canWrite else { return }
        do {
            try write(record)
            lastSaved = Date()
            saveError = nil
        } catch {
            saveError = "iPhone記録の保存失敗: \(error.localizedDescription)"
        }
    }

    private func write(_ value: HikeRecord) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: currentURL, options: .atomic)
        if value.state == .finished {
            let archive = directory.appendingPathComponent("phone-hike-\(value.id.uuidString).json")
            try data.write(to: archive, options: .atomic)
        }
    }

    /// The user explicitly chooses a durable, checksum-verified Watch snapshot.
    /// The phone begins paused and GPS continuation starts a new segment.
    func importWatchRecord(_ file: RecordExportFile) throws {
        guard canWrite, record.state != .recording else {
            throw PhoneImportError.phoneBusy
        }
        let bytes = try Data(contentsOf: file.url)
        guard bytes.count == file.byteCount,
              RecordExportFile.digest(bytes) == file.sha256 else {
            throw RecordExportError.integrityMismatch
        }
        let incoming = try HikeContinuation.restore(bytes)
        // Preserve a prior iPhone session before any attempt to replace it.
        if FileManager.default.fileExists(atPath: currentURL.path) {
            let original = try Data(contentsOf: currentURL)
            let backup = directory.appendingPathComponent("phone-before-import-\(UUID().uuidString).json")
            try original.write(to: backup, options: .atomic)
        }
        try write(incoming)
        record = incoming
        lastSaved = Date()
        saveError = nil
        infoMessage = "Watchの記録を読み込みました。iPhoneで「記録再開」を押してください"
    }
}

enum PhoneImportError: LocalizedError {
    case phoneBusy
    var errorDescription: String? { "iPhoneで記録中です。一時停止してから取り込んでください" }
}
