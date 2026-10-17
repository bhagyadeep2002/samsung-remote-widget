import Foundation

/// A bounded, one-decision hold. Network permits/delivery remain in the bridge.
/// Every clock and classifier outcome is supplied by the caller for replay tests.
struct HeldFingerVolumeSession {
    enum Phase: Equatable { case idle, preparing, sampling, waitingForRelease }
    enum Event: Equatable { case none, decide, expired }
    struct Configuration {
        var decisionDelay: TimeInterval = 2.5
        var maximumHold: TimeInterval = 10
        var maximumSampleAge: TimeInterval = 0.15
        var maximumDecisionDelay: TimeInterval = 0.15
    }
    private(set) var phase: Phase = .idle
    private(set) var generation: UUID?
    private(set) var samplingStarted: TimeInterval?
    private var started: TimeInterval = 0
    private var decisionStarted: TimeInterval?
    private var consumed = false
    private var configuration = Configuration()
    var isHeld: Bool { generation != nil && phase != .idle }

    mutating func begin(generation: UUID, now: TimeInterval, configuration: Configuration = .init()) {
        self = Self()
        guard now.isFinite else { return }
        self.configuration = configuration
        self.generation = generation
        started = now
        phase = .preparing
    }

    mutating func linkReady(generation: UUID, now: TimeInterval) -> Bool {
        guard self.generation == generation, phase == .preparing,
              now.isFinite, now >= started, now - started < configuration.maximumHold else { return false }
        samplingStarted = now
        phase = .sampling
        return true
    }

    mutating func tick(generation: UUID, now: TimeInterval) -> Event {
        guard self.generation == generation else { return .none }
        guard now.isFinite, now >= started, now - started < configuration.maximumHold else {
            cancel(); return .expired
        }
        guard phase == .sampling, let samplingStarted else { return .none }
        let elapsed = now - samplingStarted
        guard elapsed + 1e-9 >= configuration.decisionDelay else { return .none }
        guard elapsed - configuration.decisionDelay <= configuration.maximumDecisionDelay + 1e-9 else {
            cancel(); return .expired
        }
        phase = .waitingForRelease
        decisionStarted = now
        return .decide
    }

    mutating func complete(_ decision: FingerGestureClassifier.Decision, generation: UUID,
                           sampleTimestamp: TimeInterval, now: TimeInterval) -> TwistIntent? {
        guard self.generation == generation, phase == .waitingForRelease, !consumed else { return nil }
        // Even an invalid, busy, Still or Unsure outcome is consumed for this hold.
        consumed = true
        guard let decisionStarted, now.isFinite, sampleTimestamp.isFinite,
              now >= decisionStarted, now - decisionStarted < 0.25,
              now - started < configuration.maximumHold,
              sampleTimestamp <= now, now - sampleTimestamp <= configuration.maximumSampleAge else { return nil }
        let direction: TwistIntent.Direction
        switch decision {
        case .up: direction = .up
        case .down: direction = .down
        case .still, .unsure: return nil
        }
        return TwistIntent(direction: direction, generation: generation, timestamp: decisionStarted)
    }

    mutating func cancel() { self = Self() }
}
