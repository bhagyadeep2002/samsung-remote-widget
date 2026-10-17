import Foundation

/// Direct raw gyroscope access is not required. Device motion supplies calibrated
/// rotation rate independently of CMMotionManager.isGyroAvailable.
enum FingerCaptureAcquisition: String, Codable, Sendable {
    case rawAccelerometerWithDeviceMotionRotation
    case deviceMotion

    static func select(rawAccelerometer: Bool, deviceMotion: Bool) -> Self? {
        guard deviceMotion else { return nil }
        return rawAccelerometer ? .rawAccelerometerWithDeviceMotionRotation : .deviceMotion
    }

    var description: String {
        switch self {
        case .rawAccelerometerWithDeviceMotionRotation: "Raw acceleration + device-motion rotation"
        case .deviceMotion: "Device-motion acceleration + rotation"
        }
    }
}

/// Diagnostic data only. This schema is never accepted by the volume command path.
struct FingerGestureRecording: Codable, Sendable, Identifiable {
    enum Label: String, CaseIterable, Codable, Sendable { case up, down, still }
    struct Point: Codable, Sendable, Equatable {
        let time: TimeInterval // seconds from the end of touch settling
        let x: Double
        let y: Double
        let z: Double
        var isValid: Bool {
            time.isFinite && (0...4).contains(time) && x.isFinite && y.isFinite && z.isFinite
        }
    }
    let version: Int
    let id: UUID
    let label: Label
    let capturedAt: Date
    let wrist: String
    let crown: String
    let device: String
    let systemVersion: String
    let requestedInterval: TimeInterval
    let duration: TimeInterval
    let accelerometer: [Point] // device axes, g, includes gravity; source below
    let gyroscope: [Point] // device axes, radians/sec; independent timestamps
    // Version 1 is the original raw pair. Version 2 requires an explicit source:
    // deviceMotion acceleration = gravity + userAcceleration; rotationRate is
    // bias-corrected Core Motion data, not direct raw gyro measurements.
    var acquisition: FingerCaptureAcquisition? = nil

    var isValid: Bool {
        ((version == 1 && acquisition == nil) || (version == 2 && acquisition != nil)) &&
        capturedAt.timeIntervalSince1970.isFinite &&
        ["left", "right"].contains(wrist) && ["left", "right"].contains(crown) &&
        device.count <= 100 && systemVersion.count <= 100 &&
        requestedInterval.isFinite && (0.001...0.1).contains(requestedInterval) &&
        duration.isFinite && (0.8...4).contains(duration) &&
        Self.valid(accelerometer, duration: duration) && Self.valid(gyroscope, duration: duration)
    }

    private static func valid(_ points: [Point], duration: TimeInterval) -> Bool {
        guard (20...1000).contains(points.count),
              let first = points.first, let last = points.last, last.time - first.time >= 0.5 else { return false }
        var previous: TimeInterval = -.infinity
        for point in points {
            guard point.isValid, point.time <= duration, point.time > previous else { return false }
            previous = point.time
        }
        return true
    }

    static func rate(_ points: [Point]) -> Double {
        guard let first = points.first, let last = points.last, last.time > first.time else { return 0 }
        return Double(points.count - 1) / (last.time - first.time)
    }
}

/// Bounded, generation-scoped acquisition, with explicit time supplied by caller.
struct FingerCaptureBuffer {
    static let settling: TimeInterval = 0.35
    static let maximumDuration: TimeInterval = 4
    static let releaseTrim: TimeInterval = 0.1
    private(set) var generation: UUID?
    private(set) var started: TimeInterval = 0
    private(set) var accelerometer: [FingerGestureRecording.Point] = []
    private(set) var gyroscope: [FingerGestureRecording.Point] = []
    var sampleStart: TimeInterval { started + Self.settling }

    mutating func begin(generation: UUID, now: TimeInterval) {
        self = Self()
        guard now.isFinite else { return }
        self.generation = generation
        started = now
    }

    mutating func append(acceleration: Bool, timestamp: TimeInterval,
                         x: Double, y: Double, z: Double, generation: UUID, now: TimeInterval) {
        guard self.generation == generation, now.isFinite, timestamp.isFinite,
              timestamp <= now, now - timestamp <= 0.15 else { return }
        let point = FingerGestureRecording.Point(time: timestamp - sampleStart, x: x, y: y, z: z)
        guard point.isValid else { return }
        if acceleration {
            guard accelerometer.count < 1000, timestamp - sampleStart > (accelerometer.last?.time ?? -.infinity) else { return }
            accelerometer.append(point)
        } else {
            guard gyroscope.count < 1000, timestamp - sampleStart > (gyroscope.last?.time ?? -.infinity) else { return }
            gyroscope.append(point)
        }
    }

    /// Release saves only the stable pre-release window. Cancellation never calls this.
    mutating func finish(generation: UUID, now: TimeInterval) -> (TimeInterval, [FingerGestureRecording.Point], [FingerGestureRecording.Point])? {
        guard self.generation == generation else { return nil }
        defer { cancel() }
        guard now.isFinite else { return nil }
        let duration = min(Self.maximumDuration, now - sampleStart - Self.releaseTrim)
        guard duration >= 0.8 else { return nil }
        return (duration, accelerometer.filter { $0.time <= duration }, gyroscope.filter { $0.time <= duration })
    }

    mutating func cancel() { self = Self() }
}

/// Shared by the Watch and phone, each using its own private application support.
struct FingerRecordingStore {
    static let transferKind = "finger-gesture-recording-v1"
    static let maximumBytes = 2_000_000
    static let maximumRecordings = 60
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FingerRecordings", isDirectory: true)
    }
    var recordings: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func load(_ url: URL) throws -> FingerGestureRecording {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...Self.maximumBytes).contains(size) else { throw StoreError.invalidRecording }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBytes else { throw StoreError.invalidRecording }
        let recording = try JSONDecoder().decode(FingerGestureRecording.self, from: data)
        guard recording.isValid else { throw StoreError.invalidRecording }
        return recording
    }
    @discardableResult
    func save(_ recording: FingerGestureRecording) throws -> URL {
        guard recording.isValid else { throw StoreError.invalidRecording }
        let url = directory.appendingPathComponent(recording.id.uuidString).appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: url.path) || recordings.count < Self.maximumRecordings else {
            throw StoreError.full
        }
        let data = try JSONEncoder().encode(recording)
        guard data.count <= Self.maximumBytes else { throw StoreError.invalidRecording }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }
    func export() throws -> URL {
        let trials = try recordings.map(load)
        guard !trials.isEmpty else { throw StoreError.invalidRecording }
        let url = directory.appendingPathComponent("finger-gesture-export.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(trials).write(to: url, options: .atomic)
        return url
    }
    func removeAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
    enum StoreError: LocalizedError {
        case invalidRecording, full
        var errorDescription: String? {
            switch self {
            case .invalidRecording: "Recording too short, missing sensor samples, or invalid. Hold longer and retry."
            case .full: "Recording storage is full (60 trials). Export the existing trials first."
            }
        }
    }
}
