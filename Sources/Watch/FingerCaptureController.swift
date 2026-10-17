import Combine
import CoreMotion
import Foundation
import WatchKit

/// Foreground acquisition and deterministic processing. Volume delivery is
/// injected; this controller owns no network objects, credentials or queues.
@MainActor
final class FingerCaptureController: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case control, test, record
        var id: String { rawValue }
        var title: String {
            switch self { case .control: "Control TV"; case .test: "Test"; case .record: "Record" }
        }
    }
    @Published var label: FingerGestureRecording.Label = .up
    @Published var mode: Mode = .control {
        didSet { cancel(reason: "Mode changed. Hold to start again.") }
    }
    @Published private(set) var testResult = "No gesture yet"
    @Published private(set) var isRecording = false
    @Published private(set) var status = "Connect, then hold to control volume."
    @Published private(set) var counts = ""
    @Published private(set) var savedCounts = ""
    @Published private(set) var sensorStatus = ""
    @Published var deliveryStatus = ""
    var onLiveBegin: ((UUID) -> Void)?
    var onLiveIntent: ((TwistIntent) -> Void)?
    var onLiveEnd: ((UUID) -> Void)?
    private let manager = CMMotionManager()
    private var buffer = FingerCaptureBuffer()
    private var held = HeldFingerVolumeSession()
    private var generation: UUID?
    private var watchdog: Task<Void, Never>?
    private var trialLabel: FingerGestureRecording.Label = .up
    private var trialMode: Mode = .control
    private var acquisition: FingerCaptureAcquisition?
    private let store = FingerRecordingStore()
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var isLiveHeld: Bool { isRecording && trialMode == .control && held.isHeld }
    var awaitingRelease: Bool { isLiveHeld && held.phase == .waitingForRelease }
    func isLiveHeld(generation: UUID) -> Bool { isLiveHeld && self.generation == generation }

    init() { refreshCounts() }

    func begin() {
        guard !isRecording else { return }
        guard let acquisition = FingerCaptureAcquisition.select(
            rawAccelerometer: manager.isAccelerometerAvailable, deviceMotion: manager.isDeviceMotionAvailable) else {
            status = "Device motion unavailable."
            sensorStatus = "Acceleration: \(manager.isAccelerometerAvailable ? "available" : "unavailable") · Device motion: unavailable"
            return
        }
        let device = WKInterfaceDevice.current()
        if mode == .control && (acquisition != .rawAccelerometerWithDeviceMotionRotation ||
            device.wristLocation != .left || device.crownOrientation != .right) {
            status = "This model needs the recorded left-wrist, crown-right setup. Use Test or tap volume."
            return
        }
        self.acquisition = acquisition
        sensorStatus = acquisition.description
        let id = UUID()
        generation = id
        trialLabel = label
        trialMode = mode
        isRecording = true
        testResult = "Waiting for gesture…"
        counts = ""
        if trialMode == .control {
            held.begin(generation: id, now: now)
            status = "Keep holding… Preparing TV link."
            deliveryStatus = "Preparing volume link…"
            startWatchdog(generation: id)
            guard let onLiveBegin else { cancel(reason: "TV control unavailable."); return }
            onLiveBegin(id)
        } else {
            deliveryStatus = ""
            startAcquisition(generation: id)
            startWatchdog(generation: id)
        }
    }

    func volumeLinkReady(generation id: UUID) {
        guard generation == id, isLiveHeld, held.linkReady(generation: id, now: now) else { return }
        startAcquisition(generation: id)
    }

    private func startAcquisition(generation id: UUID) {
        guard generation == id, let acquisition else { return }
        buffer.begin(generation: id, now: now)
        status = "Keep still… Wait for GO."
        if acquisition == .rawAccelerometerWithDeviceMotionRotation {
            manager.accelerometerUpdateInterval = 0.01
            manager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                MainActor.assumeIsolated {
                    guard let self, self.generation == id, self.buffer.generation == id else { return }
                    guard let data, error == nil else {
                        self.cancel(reason: "Acceleration stopped. Release and try again."); return
                    }
                    self.buffer.append(acceleration: true, timestamp: data.timestamp,
                        x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z, generation: id, now: self.now)
                }
            }
        }
        manager.deviceMotionUpdateInterval = 0.01
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            MainActor.assumeIsolated {
                guard let self, self.generation == id, self.buffer.generation == id else { return }
                guard let data, error == nil else { self.cancel(reason: "Device motion stopped. Release and try again."); return }
                if acquisition == .deviceMotion {
                    self.buffer.append(acceleration: true, timestamp: data.timestamp,
                        x: data.gravity.x + data.userAcceleration.x,
                        y: data.gravity.y + data.userAcceleration.y,
                        z: data.gravity.z + data.userAcceleration.z, generation: id, now: self.now)
                }
                self.buffer.append(acceleration: false, timestamp: data.timestamp,
                    x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z, generation: id, now: self.now)
            }
        }
    }

    private func startWatchdog(generation id: UUID) {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, self.generation == id else { return }
                if self.trialMode == .control {
                    switch self.held.tick(generation: id, now: self.now) {
                    case .expired: self.cancel(reason: "Hold expired. Release and try again."); return
                    case .decide: self.recognizeWhileHeld(generation: id)
                    case .none: break
                    }
                    guard self.generation == id else { return }
                    if self.held.phase == .preparing || self.held.phase == .waitingForRelease { continue }
                    // Both streams must remain live. A stalled acquisition is
                    // discarded, never recognized later when updates resume.
                    if self.now - self.buffer.sampleStart > 0.2 {
                        guard let latest = self.latestSampleTime, self.now - latest <= 0.15 else {
                            self.cancel(reason: "Motion updates paused. Release and try again."); return
                        }
                    }
                }
                let elapsed = self.now - self.buffer.sampleStart
                if self.trialMode != .control && elapsed >= FingerCaptureBuffer.maximumDuration + FingerCaptureBuffer.releaseTrim {
                    self.finish(); return
                }
                if elapsed >= FingerGestureClassifier.cueDelayAfterSettling {
                    switch self.trialMode {
                    case .control: self.status = "GO: one gesture, then rest. Keep holding."
                    case .test: self.status = "GO: one gesture, then rest and release."
                    case .record:
                        self.status = self.trialLabel == .still ? "GO: stay still, then release." : "GO: one \(self.trialLabel.rawValue) gesture, then rest."
                    }
                }
                if elapsed >= 0 {
                    self.counts = String(format: "%.1fs · accel %d · gyro %d", elapsed,
                        self.buffer.accelerometer.count, self.buffer.gyroscope.count)
                }
            }
        }
    }

    private var latestSampleTime: TimeInterval? {
        guard let a = buffer.accelerometer.last, let g = buffer.gyroscope.last else { return nil }
        return buffer.sampleStart + min(a.time, g.time)
    }

    private func recording(generation id: UUID) -> FingerGestureRecording? {
        guard let acquisition, let (duration, acceleration, rotation) = buffer.finish(generation: id, now: now) else { return nil }
        let device = WKInterfaceDevice.current()
        let trial = FingerGestureRecording(version: 2, id: id, label: trialLabel, capturedAt: Date(),
            wrist: device.wristLocation == .left ? "left" : "right",
            crown: device.crownOrientation == .left ? "left" : "right", device: device.model,
            systemVersion: device.systemVersion, requestedInterval: 0.01, duration: duration,
            accelerometer: acceleration, gyroscope: rotation, acquisition: acquisition)
        guard trial.isValid else { return nil }
        counts = "Actual rates: accel \(Int(FingerGestureRecording.rate(acceleration).rounded())) Hz · gyro \(Int(FingerGestureRecording.rate(rotation).rounded())) Hz"
        return trial
    }

    private func recognizeWhileHeld(generation id: UUID) {
        guard isLiveHeld(generation: id), let latest = latestSampleTime,
              now - latest <= 0.15, let trial = recording(generation: id) else {
            cancel(reason: "Missing fresh motion samples. Release and try again."); return
        }
        stopAcquisition()
        let decision = FingerGestureClassifier.classify(trial)
        display(decision)
        status = "Result ready. Release before the next gesture."
        let intent = held.complete(decision, generation: id, sampleTimestamp: latest, now: now)
        if let intent { onLiveIntent?(intent) }
        else { deliveryStatus = "No command sent. Release and try again." }
    }

    /// Release can save/classify offline modes. Live release only cancels.
    func finish() {
        guard let id = generation else { return }
        if trialMode == .control { cancel(reason: "Released. Motion stopped."); return }
        let trial = recording(generation: id)
        stop()
        guard let trial else { status = "Too short or missing samples. Hold 2–3 seconds and retry."; return }
        if trialMode == .test {
            display(FingerGestureClassifier.classify(trial))
            status = "Test complete. No TV command sent."
        } else {
            do {
                try store.save(trial)
                status = "Saved \(trialLabel.rawValue). Lift finger before the next trial."
                refreshCounts()
            } catch { status = error.localizedDescription }
        }
    }

    private func display(_ decision: FingerGestureClassifier.Decision) {
        switch decision {
        case .up: testResult = "Up ↑"
        case .down: testResult = "Down ↓"
        case .still: testResult = "Still — no gesture"
        case .unsure: testResult = "Unsure — try again"
        }
    }

    func cancel(reason: String = "Cancelled. Release and try again.") {
        guard generation != nil else { return }
        stop()
        status = reason
    }

    private func stopAcquisition() {
        manager.stopAccelerometerUpdates()
        manager.stopDeviceMotionUpdates()
    }

    private func stop() {
        let oldGeneration = generation
        let wasLive = trialMode == .control
        generation = nil
        held.cancel()
        buffer.cancel()
        stopAcquisition()
        watchdog?.cancel(); watchdog = nil
        acquisition = nil
        isRecording = false
        if wasLive { deliveryStatus = "Volume control stopped" }
        if wasLive, let oldGeneration { onLiveEnd?(oldGeneration) }
    }

    func refreshCounts() {
        let trials = store.recordings.compactMap { try? store.load($0) }
        savedCounts = FingerGestureRecording.Label.allCases.map { label in
            "\(label.rawValue.capitalized): \(trials.filter { $0.label == label }.count)"
        }.joined(separator: " · ")
    }
}
