import Foundation

/// Only these typed, nonsecret values cross the live Watch/iPhone channel.
struct VolumeBridgeMessage: Codable, Sendable {
    var version = 1
    var kind: String
    var requestID = UUID().uuidString
    var sessionID: String?
    var permitID: String?
    var activationID: String?
    var activationSequence: Int?
    var sequence: Int = 0
    var direction: String?
    var status: String?
    var detail: String?
    var relayMilliseconds: Double?

    func reply(_ status: String, detail: String? = nil) -> Self {
        var result = self
        result.status = status
        result.detail = detail
        return result
    }
}

enum VolumeBridgeTiming {
    static let permitLifetime: TimeInterval = 0.5
    static let tapLifetime: TimeInterval = 0.25
    static let heartbeatInterval: TimeInterval = 0.2

    /// Start-to-start cadence; message transit already counts toward the interval.
    /// One heartbeat remains in flight, and slower links never build a backlog.
    static func refreshDelay(requestStarted: TimeInterval, now: TimeInterval) -> TimeInterval {
        max(0, heartbeatInterval - max(0, now - requestStarted))
    }
}

/// Connection readiness outlives a single-use command permit. Expiry must never
/// blink the controls or authorize an old tap when a fresh permit arrives.
struct WatchVolumeAdmission {
    private(set) var sessionID: String?
    private var permitID: String?
    private var deadline: TimeInterval = 0
    private var latestRequestStarted: TimeInterval = -.infinity

    mutating func connect(session: String) {
        sessionID = session
        permitID = nil
        deadline = 0
        latestRequestStarted = -.infinity
    }

    mutating func receivePermit(_ permit: String?, session: String,
                                requestStarted: TimeInterval) {
        guard sessionID == session, requestStarted > latestRequestStarted else { return }
        latestRequestStarted = requestStarted
        permitID = permit
        // The phone issues the permit AFTER this request starts. Adding its
        // fixed lifetime here gives a conservative bound without comparing clocks.
        // This cache lifetime is separate from the age of any actual tap.
        deadline = requestStarted + VolumeBridgeTiming.permitLifetime
    }

    mutating func takePermit(now: TimeInterval) -> String? {
        guard sessionID != nil, now < deadline else { return nil }
        defer { permitID = nil }
        return permitID
    }

    mutating func discardPermit(at now: TimeInterval) {
        permitID = nil
        deadline = 0
        latestRequestStarted = max(latestRequestStarted, now)
    }

    static func freshTap(started: TimeInterval, now: TimeInterval) -> Bool {
        now >= started && now - started < VolumeBridgeTiming.tapLifetime
    }

    mutating func end() {
        sessionID = nil
        permitID = nil
        deadline = 0
    }
}

struct MotionActivation: Equatable, Sendable {
    let sessionID: String
    let generation: UUID
    let sequence: Int
    var id: String { generation.uuidString }
}

/// One activation and one cached permit; no pending motion displacement/commands.
struct WatchMotionAdmission {
    private(set) var activation: MotionActivation?
    private(set) var ready = false
    private(set) var ending: MotionActivation?
    var canRefresh: Bool { ending == nil && (activation == nil || ready) }
    private var permits = WatchVolumeAdmission()

    mutating func begin(_ activation: MotionActivation) {
        self.activation = activation
        ready = false
        permits.connect(session: activation.sessionID)
    }
    mutating func cancel() -> MotionActivation? {
        defer { activation = nil; ready = false; permits.end() }
        if let activation { ending = activation }
        return activation
    }
    mutating func finishEnd(_ activation: MotionActivation) {
        if ending == activation { ending = nil }
    }
    mutating func reset() { self = Self() }
    func isCurrent(_ activation: MotionActivation) -> Bool { self.activation == activation }
    mutating func receive(_ reply: VolumeBridgeMessage, for activation: MotionActivation,
                          requestStarted: TimeInterval) {
        guard isCurrent(activation), reply.status == "ready",
              reply.sessionID == activation.sessionID, reply.activationID == activation.id,
              reply.activationSequence == activation.sequence else { return }
        ready = true
        // A newer accepted begin proves the older remote activation is revoked,
        // even if its end reply is delayed or lost.
        if let ending, ending.sessionID == activation.sessionID, ending.sequence < activation.sequence {
            self.ending = nil
        }
        permits.receivePermit(reply.permitID, session: activation.sessionID, requestStarted: requestStarted)
    }
    func valid(_ activation: MotionActivation, generation: UUID, timestamp: TimeInterval, now: TimeInterval) -> Bool {
        ready && isCurrent(activation) && generation == activation.generation &&
            WatchVolumeAdmission.freshTap(started: timestamp, now: now)
    }
    mutating func take(for generation: UUID, timestamp: TimeInterval, now: TimeInterval) -> (MotionActivation, String)? {
        guard let activation, valid(activation, generation: generation, timestamp: timestamp, now: now),
              let permit = permits.takePermit(now: now) else { return nil }
        return (activation, permit)
    }
}

/// A phone-clock permit is immutable. Heartbeats never extend an older permit.
/// Synchronous locking lets the transport recheck cancellation at the write boundary.
final class VolumeRelayGate: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionID: String?
    private var leaseEnd: TimeInterval = 0
    private struct Permit {
        let deadline: TimeInterval
        let activationID: String?
        let activationSequence: Int?
    }
    private var permits: [String: Permit] = [:]
    private var activationID: String?
    private var activationSequence = 0
    private var lastMotionWrite: TimeInterval = -.infinity
    private var sequence = 0
    private var requests: [String] = []
    private var lastWrite: TimeInterval = -.infinity

    func begin(now: TimeInterval) -> String {
        lock.withLock {
            let id = UUID().uuidString
            sessionID = id
            leaseEnd = now + 2
            permits.removeAll()
            requests.removeAll()
            sequence = 0
            lastWrite = -.infinity
            lastMotionWrite = -.infinity
            activationID = nil
            activationSequence = 0
            return id
        }
    }

    func beginMotion(session: String, activation: String, sequence: Int, now: TimeInterval) -> Bool {
        lock.withLock {
            guard sessionID == session, now < leaseEnd, sequence > 0 else { return false }
            if sequence == activationSequence { return activationID == activation }
            guard sequence > activationSequence else { return false }
            activationSequence = sequence
            activationID = activation
            permits.removeAll()
            return true
        }
    }

    /// A sequence watermark also rejects a delayed begin arriving AFTER its end.
    func endMotion(session: String, activation: String, sequence: Int) {
        lock.withLock {
            guard sessionID == session, sequence > 0, sequence >= activationSequence else { return }
            if sequence == activationSequence, let active = activationID, active != activation { return }
            activationSequence = sequence
            activationID = nil
            permits.removeAll()
        }
    }

    func issue(session: String, now: TimeInterval,
               activation: String? = nil, activationSequence sequence: Int? = nil) -> String? {
        lock.withLock {
            guard sessionID == session, now < leaseEnd,
                  scopeMatches(activation, sequence: sequence) else { return nil }
            leaseEnd = now + 2
            permits = permits.filter { $0.value.deadline > now }
            guard permits.count < 4 else { return nil }
            let id = UUID().uuidString
            permits[id] = Permit(deadline: now + VolumeBridgeTiming.permitLifetime,
                                 activationID: activation, activationSequence: sequence)
            return id
        }
    }

    func consume(_ message: VolumeBridgeMessage, now: TimeInterval) -> TimeInterval? {
        lock.withLock {
            let motion = message.kind == "motionStep"
            guard message.version == 1, motion || message.kind == "step",
                  motion ? message.activationID != nil : message.activationID == nil,
                  message.direction == "up" || message.direction == "down",
                  message.sessionID == sessionID, sessionID != nil, now < leaseEnd,
                  scopeMatches(message.activationID, sequence: message.activationSequence),
                  message.sequence > sequence, !requests.contains(message.requestID) else { return nil }
            // A rejected admission is consumed too: a delayed duplicate must not
            // become executable after the rate limit or connection state changes.
            sequence = message.sequence
            requests.append(message.requestID)
            if requests.count > 64 { requests.removeFirst() }
            guard let id = message.permitID, let permit = permits[id], now < permit.deadline,
                  permit.activationID == message.activationID,
                  permit.activationSequence == message.activationSequence,
                  now - lastWrite >= 0.125,
                  !motion || now - lastMotionWrite >= 0.25 else { return nil }
            permits.removeValue(forKey: id)
            lastWrite = now
            if motion { lastMotionWrite = now }
            return permit.deadline
        }
    }

    func valid(session: String, deadline: TimeInterval, now: TimeInterval,
               activation: String? = nil, activationSequence sequence: Int? = nil) -> Bool {
        lock.withLock {
            sessionID == session && now < deadline && now < leaseEnd &&
                scopeMatches(activation, sequence: sequence)
        }
    }

    private func scopeMatches(_ activation: String?, sequence: Int?) -> Bool {
        if let activation {
            return activationID == activation && sequence == activationSequence
        }
        return activationID == nil && sequence == nil
    }

    func hasLease(now: TimeInterval) -> Bool {
        lock.withLock { sessionID != nil && now < leaseEnd }
    }

    func cancel(session: String? = nil) {
        lock.withLock {
            if let session, session != sessionID { return }
            sessionID = nil
            activationID = nil
            permits.removeAll()
            leaseEnd = 0
        }
    }
}

#if os(iOS) || os(watchOS)
@preconcurrency import WatchConnectivity

private final class BridgeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: CheckedContinuation<VolumeBridgeMessage, Error>?
    init(_ completion: CheckedContinuation<VolumeBridgeMessage, Error>) { self.completion = completion }
    func finish(_ result: Result<VolumeBridgeMessage, Error>) {
        let pending = lock.withLock { let value = completion; completion = nil; return value }
        pending?.resume(with: result)
    }
}

enum VolumeBridgeWire {
    @MainActor
    static func send(_ message: VolumeBridgeMessage, session: WCSession,
                     validity: @MainActor () -> Bool = { true }) async throws -> VolumeBridgeMessage {
        guard validity() else { throw CancellationError() }
        guard session.activationState == .activated, session.isReachable else { throw BridgeError.unavailable }
        let data = try JSONEncoder().encode(message)
        return try await withCheckedThrowingContinuation { continuation in
            // MainActor cannot process stop/cancel between this check and the
            // synchronous WCSession call. Commands already in transit are bounded
            // separately by the relay activation and immutable permit deadline.
            guard validity() else { continuation.resume(throwing: CancellationError()); return }
            let completion = BridgeCompletion(continuation)
            session.sendMessage(["payload": data], replyHandler: { payload in
                guard let data = payload["payload"] as? Data,
                      let reply = try? JSONDecoder().decode(VolumeBridgeMessage.self, from: data),
                      reply.version == 1, reply.requestID == message.requestID else {
                    completion.finish(.failure(BridgeError.invalidReply)); return
                }
                completion.finish(.success(reply))
            }, errorHandler: { _ in completion.finish(.failure(BridgeError.unavailable)) })
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                completion.finish(.failure(BridgeError.timeout))
            }
        }
    }

    enum BridgeError: Error { case unavailable, invalidReply, timeout }
}
#endif
