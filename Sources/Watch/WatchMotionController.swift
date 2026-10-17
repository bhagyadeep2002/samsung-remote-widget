import Combine
import Foundation
import WatchKit

/// Foreground acquisition/processing. Delivery is injected as discrete callbacks;
/// this controller owns neither networking nor command queues.
@MainActor
final class WatchMotionController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Keep still briefly to calibrate, then twist."
    @Published private(set) var angleDegrees = 0.0
    @Published private(set) var preview = "No twist yet"
    var onBegin: ((UUID) -> Void)?
    var onIntent: ((TwistIntent) -> Void)?
    var onEnd: ((UUID) -> Void)?
    @Published var deliveryStatus = "Connect to start motion."
    @Published private(set) var sensorStatus = "Motion not sampled"
    @Published var axis: GestureConfiguration.Axis = .x {
        didSet {
            UserDefaults.standard.set(axis.rawValue, forKey: "motionPreviewAxis")
            inverted = UserDefaults.standard.object(forKey: directionKey) as? Bool ?? true
            stop(reason: "Axis changed. Tap Recalibrate.")
        }
    }
    @Published var inverted = true {
        didSet {
            UserDefaults.standard.set(inverted, forKey: directionKey)
            stop(reason: "Direction changed. Tap Recalibrate.")
        }
    }
    let orientation: String
    private let wrist: GestureConfiguration.Wrist
    private let crown: GestureConfiguration.Crown
    private let source = WatchMotionSource()
    private var processor = WristTwistProcessor()
    private var generation: UUID?
    private var watchdog: Task<Void, Never>?
    private var previousPhase: WristTwistProcessor.Phase = .idle
    private var sampleCount = 0
    private var firstSampleTime: TimeInterval?
    private var directionKey: String {
        "motionPreviewReversed.\(wrist == .left ? "left" : "right").\(crown == .left ? "left" : "right").\(axis.rawValue)"
    }

    init() {
        let device = WKInterfaceDevice.current()
        wrist = device.wristLocation == .left ? .left : .right
        crown = device.crownOrientation == .left ? .left : .right
        orientation = "\(device.wristLocation == .left ? "Left" : "Right") wrist · Crown \(device.crownOrientation == .left ? "left" : "right")"
        axis = UserDefaults.standard.string(forKey: "motionPreviewAxis")
            .flatMap(GestureConfiguration.Axis.init(rawValue:)) ?? .x
        // Wearer reports the first preview's sign is reversed. Apply the observed
        // correction, preserving explicit choices per wrist/crown/axis afterward.
        inverted = UserDefaults.standard.object(forKey: directionKey) as? Bool ?? true
    }

    func begin(connected: Bool) {
        guard !isRunning else { return }
        guard connected else { status = "Connect to the TV first."; return }
        guard source.available else { status = "Motion unavailable. Use the volume buttons."; return }
        var config = GestureConfiguration()
        config.axis = axis; config.inverted = inverted
        config.wrist = wrist; config.crown = crown
        // User chose continuous app-active operation; lifecycle and range/sample
        // safeguards replace the former ten-second touch-hold limit.
        config.maximumHold = .infinity
        let id = UUID()
        generation = id
        isRunning = true
        sampleCount = 0; firstSampleTime = nil
        angleDegrees = 0
        preview = "No twist yet"
        status = "Keep wrist still… Calibrating"
        previousPhase = .calibrating
        processor.begin(generation: id, configuration: config, now: ProcessInfo.processInfo.systemUptime)
        onBegin?(id)
        guard generation == id else { return }
        let reference = source.start(generation: id, interval: config.sampleInterval,
            onSample: { [weak self] sample in self?.receive(sample, generation: id) },
            onError: { [weak self] message in
                guard self?.generation == id else { return }
                self?.stop(reason: message)
            })
        guard generation == id else { return }
        sensorStatus = reference.map { "\($0) · Awaiting samples" } ?? "Motion unavailable"
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, self.generation == id else { return }
                self.processor.tick(now: ProcessInfo.processInfo.systemUptime, generation: id)
                self.updatePhase()
            }
        }
    }

    private func receive(_ sample: MotionSample, generation id: UUID) {
        guard generation == id, isRunning else { return }
        let intent = processor.handle(sample, generation: id, now: ProcessInfo.processInfo.systemUptime)
        sampleCount += 1
        firstSampleTime = firstSampleTime ?? sample.timestamp
        if sampleCount.isMultiple(of: 10), let first = firstSampleTime, sample.timestamp > first {
            let rate = Double(sampleCount - 1) / (sample.timestamp - first)
            sensorStatus = "Live motion: \(Int(rate.rounded())) samples/s"
        }
        let rounded = processor.angleDegrees.rounded()
        if angleDegrees != rounded { angleDegrees = rounded }
        updatePhase()
        if let intent {
            preview = intent.direction == .up ? "+ Volume up gesture" : "− Volume down gesture"
            WKInterfaceDevice.current().play(.click)
            onIntent?(intent)
        }
    }

    private func updatePhase() {
        guard processor.phase != previousPhase else { return }
        previousPhase = processor.phase
        switch processor.phase {
        case .active:
            status = "Motion active. Twist to change volume."
            WKInterfaceDevice.current().play(.start)
        case let .recenter(reason): stop(reason: reason)
        case .idle, .calibrating: break
        }
    }

    func stop(reason: String? = nil) {
        let oldGeneration = generation
        let wasRunning = isRunning
        generation = nil
        source.stop()
        watchdog?.cancel()
        watchdog = nil
        processor.stop()
        previousPhase = .idle
        isRunning = false
        if let reason { status = reason }
        else if wasRunning { status = "Motion paused." }
        if let oldGeneration { onEnd?(oldGeneration) }
    }
}
