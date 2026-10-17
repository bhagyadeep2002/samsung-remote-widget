import Foundation

/// Pure processing: all time, samples and lifecycle events arrive from callers.
/// No Core Motion, clock reads, persistence, UI or command delivery.
struct WristTwistProcessor {
    enum Phase: Equatable {
        case idle, calibrating, active
        case recenter(String)
    }
    private(set) var phase: Phase = .idle
    private(set) var angleDegrees = 0.0
    private(set) var generation: UUID?
    private var configuration = GestureConfiguration()
    private var started: TimeInterval = 0
    private var lastTime: TimeInterval?
    private var previousQuaternion: MotionQuaternion?
    private var quietStart: TimeInterval?
    private var quietReference: MotionQuaternion?
    private var quietGravity: MotionVector?
    private var sum = MotionQuaternion(x: 0, y: 0, z: 0, w: 0)
    private var neutral: MotionQuaternion?
    private var previousWrapped = 0.0
    private var unwrapped = 0.0
    private var filtered = 0.0
    private var anchor = 0.0
    private var extreme = 0.0
    private var trend = 0.0
    private var lastIntent: TimeInterval = -.infinity

    mutating func begin(generation: UUID, configuration: GestureConfiguration, now: TimeInterval) {
        self = Self()
        self.generation = generation
        self.configuration = configuration
        started = now
        phase = .calibrating
    }

    mutating func stop() { self = Self() }

    mutating func requireRecenter(_ reason: String) {
        phase = .recenter(reason)
        generation = nil
        neutral = nil
        quietReference = nil
        quietGravity = nil
        quietStart = nil
        sum = MotionQuaternion(x: 0, y: 0, z: 0, w: 0)
        anchor = 0
        trend = 0
    }

    mutating func tick(now: TimeInterval, generation: UUID) {
        guard self.generation == generation else { return }
        if now - started >= configuration.maximumHold {
            requireRecenter("Session limit reached. Recalibrate.")
        } else if phase == .calibrating && now - started >= configuration.calibrationTimeout {
            requireRecenter("Could not calibrate. Keep still and recalibrate.")
        } else if let lastTime, now - lastTime > configuration.maximumSampleAge {
            requireRecenter("Motion updates paused. Recalibrate.")
        }
    }

    mutating func handle(_ sample: MotionSample, generation: UUID, now: TimeInterval) -> TwistIntent? {
        guard self.generation == generation, phase == .calibrating || phase == .active else { return nil }
        tick(now: now, generation: generation)
        guard self.generation == generation else { return nil }
        guard sample.timestamp.isFinite, now.isFinite,
              sample.rotationRate.isFinite, sample.gravity.isFinite, sample.userAcceleration.isFinite,
              var q = sample.attitude.normalized else {
            requireRecenter("Invalid motion sample. Recalibrate."); return nil
        }
        // Core Motion can initially deliver a cached sample from just before
        // activation. Discard it without aborting a new calibration.
        guard sample.timestamp >= started else { return nil }
        guard sample.timestamp <= now,
              now - sample.timestamp <= configuration.maximumSampleAge else {
            requireRecenter("Motion sample is stale. Recalibrate."); return nil
        }
        if let lastTime, sample.timestamp <= lastTime { return nil }
        let dt = lastTime.map { sample.timestamp - $0 } ?? configuration.sampleInterval
        guard dt <= configuration.maximumSampleGap else {
            requireRecenter("Motion updates paused. Recalibrate."); return nil
        }
        lastTime = sample.timestamp
        if let previousQuaternion, previousQuaternion.dot(q) < 0 { q = q.scaled(-1) }
        previousQuaternion = q
        if phase == .calibrating {
            calibrate(q, sample: sample)
            return nil
        }
        guard let neutral else { return nil }
        let relative = neutral.conjugate * q
        let axis = configuration.twistAxis
        let projection = MotionVector(x: relative.x, y: relative.y, z: relative.z).dot(axis)
        let magnitude = hypot(relative.w, projection)
        guard magnitude > 0.000001 else {
            requireRecenter("Move back to a comfortable pose and recalibrate."); return nil
        }
        let twist = MotionQuaternion(x: axis.x * projection / magnitude,
                                     y: axis.y * projection / magnitude,
                                     z: axis.z * projection / magnitude, w: relative.w / magnitude)
        let swing = relative * twist.conjugate
        let swingDegrees = 2 * acos(min(1, abs(swing.w))) * 180 / .pi
        guard swingDegrees <= configuration.maximumSwingDegrees else {
            requireRecenter("Arm moved off axis. Recalibrate."); return nil
        }
        let wrapped = Self.wrap(2 * atan2(projection, relative.w))
        let delta = Self.wrap(wrapped - previousWrapped)
        previousWrapped = wrapped
        guard abs(delta) * 180 / .pi <= max(10, configuration.maximumSpeedDegrees * dt) else {
            requireRecenter("Motion jumped. Recalibrate."); return nil
        }
        unwrapped += delta * 180 / .pi
        guard abs(unwrapped) <= configuration.maximumTwistDegrees else {
            requireRecenter("Twist limit reached. Recalibrate."); return nil
        }
        let alpha = configuration.filterTimeConstant > 0 ? 1 - exp(-dt / configuration.filterTimeConstant) : 1
        filtered += alpha * (unwrapped - filtered)
        angleDegrees = filtered * (configuration.inverted ? -1 : 1)
        if trend == 0 {
            guard abs(filtered) > configuration.deadZoneDegrees else { return nil }
            trend = filtered > 0 ? 1 : -1
            anchor = trend * configuration.deadZoneDegrees
            extreme = filtered
        }
        if (filtered - extreme) * trend >= 0 { extreme = filtered }
        if (extreme - filtered) * trend >= configuration.reversalDegrees {
            trend = -trend
            anchor = extreme + trend * configuration.reversalDegrees
            extreme = filtered
        }
        guard (filtered - anchor) * trend + 1e-9 >= configuration.detentDegrees else { return nil }
        // Consume all displacement at this crossing, even if rate limited. There
        // is no retained backlog and a fixed pose cannot emit a later catch-up.
        anchor = filtered
        guard sample.timestamp - lastIntent >= configuration.commandInterval else { return nil }
        lastIntent = sample.timestamp
        let sign = trend * (configuration.inverted ? -1 : 1)
        return TwistIntent(direction: sign > 0 ? .up : .down, generation: generation, timestamp: sample.timestamp)
    }

    private mutating func calibrate(_ q: MotionQuaternion, sample: MotionSample) {
        let quiet = sample.rotationRate.length * 180 / .pi < configuration.calibrationSpeedDegrees &&
            sample.userAcceleration.length < configuration.calibrationAcceleration &&
            (0.8...1.2).contains(sample.gravity.length)
        if !quiet {
            quietStart = nil; quietReference = nil; quietGravity = nil
            sum = MotionQuaternion(x: 0, y: 0, z: 0, w: 0)
            return
        }
        let moved = quietReference.map {
            2 * acos(min(1, abs($0.dot(q)))) * 180 / .pi > configuration.calibrationSpreadDegrees
        } ?? false
        let gravityMoved = quietGravity.map {
            acos(max(-1, min(1, $0.dot(sample.gravity) / ($0.length * sample.gravity.length)))) * 180 / .pi > configuration.calibrationSpreadDegrees
        } ?? false
        if quietStart == nil || moved || gravityMoved {
            quietStart = sample.timestamp
            quietReference = q
            quietGravity = sample.gravity
            sum = MotionQuaternion(x: 0, y: 0, z: 0, w: 0)
        }
        let aligned = (quietReference?.dot(q) ?? 1) < 0 ? q.scaled(-1) : q
        sum = sum.adding(aligned)
        if sample.timestamp - (quietStart ?? sample.timestamp) >= configuration.calibrationDuration {
            neutral = sum.normalized
            if neutral != nil { phase = .active }
        }
    }

    private static func wrap(_ radians: Double) -> Double {
        var value = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi }
        if value < -.pi { value += 2 * .pi }
        return value
    }
}
