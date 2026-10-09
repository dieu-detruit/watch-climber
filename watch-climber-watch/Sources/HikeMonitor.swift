import SwiftUI
import CoreLocation
import HealthKit

@MainActor
final class HikeMonitor: NSObject, ObservableObject, CLLocationManagerDelegate, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    @Published var fix: Fix?
    @Published var record = HikeRecord()
    @Published var heartRate: Double?
    @Published var locationMessage = "位置を取得中"
    @Published var workoutMessage: String?
    @Published var saveMessage: String?
    @Published var starting = false
    @Published var finishing = false
    let terrain = Terrain.load()
    private let location = CLLocationManager()
    private let health = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lastSave = Date.distantPast
    private var heartDate: Date?
    private var ticker: Timer?
    private var completingWorkout = false
    private let storageURL: URL

    override init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = directory.appendingPathComponent("current-hike.json")
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
        location.activityType = .fitness
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.record.state == .recording else { return }
                self.record.advanceTime(to: Date())
                if Date().timeIntervalSince(self.lastSave) >= 10 { self.persist() }
            }
        }
        if FileManager.default.fileExists(atPath: storageURL.path) {
            do {
                record = try JSONDecoder().decode(HikeRecord.self, from: Data(contentsOf: storageURL))
                record.prepareAfterRestore()
            } catch { saveMessage = "前の記録を読み込めませんでした" }
        }
    }

    func requestLocation() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: location.startUpdatingLocation()
        case .restricted, .denied: locationMessage = "設定で位置情報を許可してください"
        @unknown default: locationMessage = "位置情報の許可を確認してください"
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
                let next = Fix(date: value.timestamp, latitude: value.coordinate.latitude,
                               longitude: value.coordinate.longitude,
                               altitude: value.verticalAccuracy >= 0 && value.verticalAccuracy <= 50 ? value.altitude : nil,
                               accuracy: value.horizontalAccuracy)
                self.fix = next
                self.locationMessage = next.usable ? "GPS" : "GPS精度不足"
                self.record.ingest(next)
            }
            if Date().timeIntervalSince(self.lastSave) >= 10 && self.record.state == .recording { self.persist() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationMessage = "位置を取得できません"
            self.record.breakTrack()
        }
    }

    func start() async {
        guard !starting, !finishing, record.state != .recording else { return }
        if record.state == .finished && saveMessage != nil { return }
        guard location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways else {
            requestLocation()
            workoutMessage = "位置情報を許可してから開始してください"
            return
        }
        starting = true
        workoutMessage = nil
        defer { starting = false }
        do {
            let heart = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [heart])
            guard health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                workoutMessage = "記録にはヘルスケアのワークアウト許可が必要です"
                return
            }
            let config = HKWorkoutConfiguration()
            config.activityType = .hiking
            config.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: health, configuration: config)
            let live = session.associatedWorkoutBuilder()
            session.delegate = self
            live.delegate = self
            live.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: config)
            workout = session
            builder = live
            heartRate = nil
            heartDate = nil
            let date = Date()
            session.startActivity(with: date)
            try await live.beginCollection(at: date)
            guard workout === session else { throw CancellationError() }
            if record.state != .paused { record = HikeRecord() }
            record.resume()
            location.allowsBackgroundLocationUpdates = true
            location.startUpdatingLocation()
            persist()
        } catch {
            workout?.end()
            builder?.discardWorkout()
            workout = nil
            builder = nil
            workoutMessage = "ワークアウトを開始できません: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard record.state == .recording else { return }
        record.advanceTime(to: Date())
        record.pause()
        workout?.pause()
        location.allowsBackgroundLocationUpdates = false
        persist()
    }
    func resume() async {
        if let workout {
            workout.resume()
            location.allowsBackgroundLocationUpdates = true
            record.resume()
            persist()
        } else { await start() }
    }
    func finish() async {
        guard !finishing else { return }
        finishing = true
        record.advanceTime(to: Date())
        record.pause()
        record.state = .finished
        persist()
        location.allowsBackgroundLocationUpdates = false
        if let workout {
            if workout.state == .ended { await completeWorkout(at: Date()) }
            else { workout.end() } // Builder completion is sequenced after the .ended delegate event.
        } else { finishing = false }
    }
    private func completeWorkout(at date: Date) async {
        guard !completingWorkout else { return }
        completingWorkout = true
        let live = builder
        workout = nil
        builder = nil
        if let live {
            do {
                try await live.endCollection(at: date)
                _ = try await live.finishWorkout()
            } catch { workoutMessage = "ヘルスケア保存失敗: \(error.localizedDescription)" }
        }
        completingWorkout = false
        finishing = false
    }
    func persist() {
        do {
            let data = try JSONEncoder().encode(record)
            try data.write(to: storageURL, options: .atomic)
            if record.state == .finished {
                let archive = storageURL.deletingLastPathComponent().appendingPathComponent("hike-\(record.id.uuidString).json")
                try data.write(to: archive, options: .atomic)
            }
            lastSave = Date()
            saveMessage = nil
        } catch { saveMessage = "保存失敗: \(error.localizedDescription)" }
    }
    func currentHeartRate(at date: Date) -> Double? {
        guard let heartDate, date.timeIntervalSince(heartDate) < 30, record.state == .recording else { return nil }
        return heartRate
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.workout === workoutSession else { return }
            switch toState {
            case .paused:
                if self.record.state == .recording {
                    self.record.advanceTime(to: date)
                    self.record.pause()
                    self.location.allowsBackgroundLocationUpdates = false
                    self.persist()
                }
            case .running:
                if self.record.state == .paused && !self.starting && !self.finishing {
                    self.record.resume(at: date)
                    self.location.allowsBackgroundLocationUpdates = true
                    self.persist()
                }
            case .ended:
                self.location.allowsBackgroundLocationUpdates = false
                if self.finishing { await self.completeWorkout(at: date) }
                else {
                    if self.record.state == .recording {
                        self.record.advanceTime(to: date)
                        self.record.pause()
                    }
                    self.workoutMessage = "ワークアウトが終了しました。再開すると新しいワークアウトを作ります"
                    self.workout = nil
                    self.builder?.discardWorkout()
                    self.builder = nil
                    self.persist()
                }
            default: break
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.workout === workoutSession else { return }
            if self.record.state == .recording {
                self.record.advanceTime(to: Date())
                self.record.pause()
            }
            self.location.allowsBackgroundLocationUpdates = false
            self.workoutMessage = "ワークアウト停止: \(error.localizedDescription)"
            self.workout = nil
            self.builder?.discardWorkout()
            self.builder = nil
            self.finishing = false
            self.persist()
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heart = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        guard collectedTypes.contains(heart), let stats = workoutBuilder.statistics(for: heart),
              let quantity = stats.mostRecentQuantity() else { return }
        let value = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let date = stats.mostRecentQuantityDateInterval()?.end ?? Date()
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.heartRate = value; self.heartDate = date
        }
    }
}
