import Foundation
import XCTest

final class PersistentRemoteConnectionTests: XCTestCase {
    func testBoundedVolumeNeverConnectsOrSendsExpiredWork() async throws {
        let socket = FakeTransport()
        let factory = FakeConnector(sockets: [socket])
        let remote = PersistentRemoteConnection { try await factory.connect($0) }
        do {
            try await remote.sendReady("up", host: "tv", valid: { true })
            XCTFail("Cold volume must be rejected")
        } catch is CancellationError { }
        let coldHosts = await factory.hosts
        XCTAssertTrue(coldHosts.isEmpty)
        try await remote.prepare(host: "tv")
        do {
            try await remote.sendReady("old-up", host: "tv", valid: { false })
            XCTFail("Expired volume must be rejected at the write boundary")
        } catch is CancellationError { }
        XCTAssertTrue(socket.messages.isEmpty)
        try await remote.sendReady("fresh-down", host: "tv", valid: { true })
        XCTAssertEqual(socket.messages, ["fresh-down"])
        await remote.disconnect()
    }

    func testBoundedVolumeIsRejectedDuringHandshakeAndAfterDisconnect() async throws {
        let gate = Gate()
        let socket = FakeTransport()
        let remote = PersistentRemoteConnection { _ in await gate.wait(); return socket }
        let warmup = Task { try await remote.prepare(host: "tv") }
        await gate.waitUntilEntered()
        do {
            try await remote.sendReady("up", host: "tv", valid: { true })
            XCTFail("Must not wait through a handshake")
        } catch is CancellationError { }
        await gate.open()
        try await warmup.value
        await remote.disconnect()
        do {
            try await remote.sendReady("down", host: "tv", valid: { true })
            XCTFail("Must not reconnect")
        } catch is CancellationError { }
        XCTAssertTrue(socket.messages.isEmpty)
    }

    func testBoundedVolumeDropsConcurrentInputAndDoesNotReplayFailedWrite() async throws {
        let writeGate = Gate()
        let socket = FakeTransport(failWrites: true, writeGate: writeGate)
        let remote = PersistentRemoteConnection { _ in socket }
        await remote.adopt(socket, host: "tv")
        let first = Task { try await remote.sendReady("up", host: "tv", valid: { true }) }
        await writeGate.waitUntilEntered()
        do {
            try await remote.sendReady("down", host: "tv", valid: { true })
            XCTFail("Must not queue concurrent input")
        } catch is CancellationError { }
        do {
            try await remote.send("ordinary-key", host: "tv")
            XCTFail("Ordinary commands cannot interleave with bounded volume")
        } catch is CancellationError { }
        await writeGate.open()
        do { try await first.value; XCTFail("Expected failure") } catch FakeError.offline { }
        XCTAssertEqual(socket.messages, ["up"])
        XCTAssertTrue(socket.isClosed)
        await remote.disconnect()
    }

    func testReceiveFailureRevokesVolumePermitBeforeFreshInput() async throws {
        let lost = expectation(description: "Receive failure revokes live session")
        let gate = VolumeRelayGate()
        let socket = FakeTransport()
        let remote = PersistentRemoteConnection(onDisconnect: {
            if gate.hasLease(now: 0) {
                gate.cancel()
                lost.fulfill()
            }
        }) { _ in socket }
        await remote.adopt(socket, host: "tv")
        let id = gate.begin(now: 0)
        let permit = try XCTUnwrap(gate.issue(session: id, now: 0))
        let step = VolumeBridgeMessage(kind: "step", sessionID: id, permitID: permit,
                                       sequence: 1, direction: "up")
        let deadline = try XCTUnwrap(gate.consume(step, now: 0.1))
        socket.close()
        await fulfillment(of: [lost], timeout: 2)
        XCTAssertFalse(gate.valid(session: id, deadline: deadline, now: 0.2))
        do {
            try await remote.sendReady("stale-up", host: "tv", valid: {
                gate.valid(session: id, deadline: deadline, now: 0.2)
            })
            XCTFail("Receive loss must not reconnect and replay volume")
        } catch is CancellationError { }
        XCTAssertTrue(socket.messages.isEmpty)
        await remote.disconnect()
    }

    func testMotionCancellationDuringDelayedAdmissionPreventsSocketWrite() async throws {
        let socket = FakeTransport()
        let remote = PersistentRemoteConnection { _ in socket }
        await remote.adopt(socket, host: "tv")
        let validity = VolumeRelayGate()
        let session = validity.begin(now: 0)
        XCTAssertTrue(validity.beginMotion(session: session, activation: "motion", sequence: 1, now: 0))
        let permit = try XCTUnwrap(validity.issue(session: session, now: 0, activation: "motion", activationSequence: 1))
        let request = VolumeBridgeMessage(kind: "motionStep", sessionID: session, permitID: permit,
            activationID: "motion", activationSequence: 1, sequence: 1, direction: "up")
        let deadline = try XCTUnwrap(validity.consume(request, now: 0.1))
        let admissionGate = Gate()
        let send = Task {
            await admissionGate.wait()
            try await remote.sendReady("up", host: "tv", valid: {
                validity.valid(session: session, deadline: deadline, now: 0.2,
                    activation: "motion", activationSequence: 1)
            })
        }
        await admissionGate.waitUntilEntered()
        validity.endMotion(session: session, activation: "motion", sequence: 1)
        await admissionGate.open()
        do { try await send.value; XCTFail("Cancelled activation must never reach the socket") }
        catch is CancellationError { }
        XCTAssertTrue(socket.messages.isEmpty)
        await remote.disconnect()
    }

    func testMotionStopAllowsOnlyAnAlreadyStartedWriteAndNoQueuedFollowup() async throws {
        let writes = Gate()
        let socket = FakeTransport(writeGate: writes)
        let remote = PersistentRemoteConnection { _ in socket }
        await remote.adopt(socket, host: "tv")
        let validity = VolumeRelayGate()
        let session = validity.begin(now: 0)
        XCTAssertTrue(validity.beginMotion(session: session, activation: "motion", sequence: 1, now: 0))
        let send = Task {
            try await remote.sendReady("already-started", host: "tv", valid: {
                validity.valid(session: session, deadline: 0.5, now: 0.1,
                    activation: "motion", activationSequence: 1)
            })
        }
        await writes.waitUntilEntered()
        validity.endMotion(session: session, activation: "motion", sequence: 1)
        do {
            try await remote.sendReady("late", host: "tv", valid: {
                validity.valid(session: session, deadline: 0.5, now: 0.2,
                    activation: "motion", activationSequence: 1)
            })
            XCTFail("No follow-up may be queued")
        } catch is CancellationError { }
        await writes.open()
        try await send.value
        XCTAssertEqual(socket.messages, ["already-started"])
        await remote.disconnect()
    }

    func testBatchesCannotInterleaveDuringAnimationDelays() async throws {
        let socket = FakeTransport()
        let remote = PersistentRemoteConnection { _ in socket }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for prefix in ["a", "b"] {
                group.addTask {
                    try await remote.send([
                        RemoteCommandStep(message: "\(prefix)-arrow", delayAfter: .milliseconds(1)),
                        RemoteCommandStep(message: "\(prefix)-enter", delayAfter: .zero)
                    ], host: "tv")
                }
            }
            try await group.waitForAll()
        }
        XCTAssertTrue(
            socket.messages == ["a-arrow", "a-enter", "b-arrow", "b-enter"] ||
            socket.messages == ["b-arrow", "b-enter", "a-arrow", "a-enter"]
        )
        await remote.disconnect()
    }

    func testBurstReusesOneConnectionAndSerializesWrites() async throws {
        let socket = FakeTransport()
        let factory = FakeConnector(sockets: [socket])
        let remote = PersistentRemoteConnection { try await factory.connect($0) }
        try await remote.prepare(host: "tv")

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask { try await remote.send("key-\(index)", host: "tv") }
            }
            try await group.waitForAll()
        }

        let hosts = await factory.hosts
        XCTAssertEqual(hosts, ["tv"])
        XCTAssertEqual(Set(socket.messages), Set((0..<40).map { "key-\($0)" }))
        XCTAssertEqual(socket.maximumConcurrentWrites, 1)
        XCTAssertFalse(socket.isClosed)
        await remote.disconnect()
        XCTAssertTrue(socket.isClosed)
    }

    func testWarmupAndClickShareAnInProgressHandshake() async throws {
        let gate = Gate()
        let socket = FakeTransport()
        let factory = FakeConnector(sockets: [socket], gate: gate)
        let remote = PersistentRemoteConnection { try await factory.connect($0) }
        let warmup = Task { try await remote.prepare(host: "tv") }
        await gate.waitUntilEntered()
        let click = Task { try await remote.send("up", host: "tv") }
        await gate.open()
        try await warmup.value
        try await click.value
        let hosts = await factory.hosts
        XCTAssertEqual(hosts, ["tv"])
        XCTAssertEqual(socket.messages, ["up"])
        await remote.disconnect()
    }

    func testFailedWriteIsNotReplayedAndNextClickReconnects() async throws {
        let first = FakeTransport(failWrites: true)
        let second = FakeTransport()
        let factory = FakeConnector(sockets: [first, second])
        let remote = PersistentRemoteConnection { try await factory.connect($0) }

        do {
            try await remote.send("volume-up", host: "tv")
            XCTFail("Expected a failed write")
        } catch FakeError.offline { }
        let hostsAfterFailure = await factory.hosts
        XCTAssertEqual(hostsAfterFailure.count, 1, "An ambiguous write must never be retried automatically")
        XCTAssertEqual(first.messages, ["volume-up"])
        XCTAssertTrue(first.isClosed)

        try await remote.send("down", host: "tv")
        XCTAssertEqual(second.messages, ["down"])
        let hostsAfterNextClick = await factory.hosts
        XCTAssertEqual(hostsAfterNextClick.count, 2)
        await remote.disconnect()
    }

    func testLateHandshakeCannotReplaceNewlyPairedTV() async throws {
        let gate = Gate()
        let oldSocket = FakeTransport()
        let newSocket = FakeTransport()
        let factory = FakeConnector(sockets: [oldSocket], gate: gate)
        let remote = PersistentRemoteConnection { try await factory.connect($0) }
        let oldWarmup = Task { try await remote.prepare(host: "old-tv") }
        await gate.waitUntilEntered()

        await remote.disconnect()
        await remote.adopt(newSocket, host: "new-tv")
        await gate.open()
        do {
            try await oldWarmup.value
            XCTFail("An obsolete handshake must be discarded")
        } catch is CancellationError { }

        try await remote.send("home", host: "new-tv")
        XCTAssertTrue(oldSocket.isClosed)
        XCTAssertFalse(newSocket.isClosed)
        XCTAssertEqual(newSocket.messages, ["home"])
        await remote.disconnect()
    }

    func testAdoptsPairingSocketWithoutAnotherHandshake() async throws {
        let socket = FakeTransport()
        let factory = FakeConnector(sockets: [])
        let remote = PersistentRemoteConnection { try await factory.connect($0) }
        await remote.adopt(socket, host: "tv")
        try await remote.send("select", host: "tv")
        let hosts = await factory.hosts
        XCTAssertTrue(hosts.isEmpty)
        XCTAssertEqual(socket.messages, ["select"])
        await remote.disconnect()
    }

    func testKeepaliveReconnectsAfterLostConnection() async throws {
        let reconnected = expectation(description: "Reconnected and pinged without a button press")
        let first = FakeTransport(failPings: true)
        let second = FakeTransport(onPing: { reconnected.fulfill() })
        let factory = FakeConnector(sockets: [first, second])
        let remote = PersistentRemoteConnection(keepaliveInterval: .milliseconds(10)) {
            try await factory.connect($0)
        }
        try await remote.prepare(host: "tv")
        await fulfillment(of: [reconnected], timeout: 2)
        let hosts = await factory.hosts
        XCTAssertEqual(hosts.count, 2)
        XCTAssertTrue(first.isClosed)
        await remote.disconnect()
    }

    func testChangingAddressClosesPreviousConnection() async throws {
        let first = FakeTransport()
        let second = FakeTransport()
        let factory = FakeConnector(sockets: [first, second])
        let remote = PersistentRemoteConnection { try await factory.connect($0) }
        try await remote.prepare(host: "old-tv")
        try await remote.send("home", host: "new-tv")
        let hosts = await factory.hosts
        XCTAssertEqual(hosts, ["old-tv", "new-tv"])
        XCTAssertTrue(first.isClosed)
        XCTAssertTrue(first.messages.isEmpty)
        XCTAssertEqual(second.messages, ["home"])
        await remote.disconnect()
    }
}

private enum FakeError: Error { case offline }

private actor Gate {
    private var isOpen = false
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        for waiter in entryWaiters { waiter.resume() }
        entryWaiters.removeAll()
        if !isOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func waitUntilEntered() async {
        if !entered {
            await withCheckedContinuation { entryWaiters.append($0) }
        }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

private actor FakeConnector {
    private let sockets: [FakeTransport]
    private let gate: Gate?
    private(set) var hosts: [String] = []

    init(sockets: [FakeTransport], gate: Gate? = nil) {
        self.sockets = sockets
        self.gate = gate
    }

    func connect(_ host: String) async throws -> any RemoteTransport {
        let index = hosts.count
        hosts.append(host)
        if let gate { await gate.wait() }
        guard sockets.indices.contains(index) else { throw FakeError.offline }
        return sockets[index]
    }
}

private final class FakeTransport: RemoteTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var closed = false
    private var activeWrites = 0
    private var maximumWrites = 0
    private var receiver: CheckedContinuation<Void, Error>?
    private let writeGate: Gate?
    private let failWrites: Bool
    private let failPings: Bool
    private let onPing: @Sendable () -> Void

    init(failWrites: Bool = false, failPings: Bool = false, writeGate: Gate? = nil, onPing: @escaping @Sendable () -> Void = {}) {
        self.writeGate = writeGate
        self.failWrites = failWrites
        self.failPings = failPings
        self.onPing = onPing
    }

    var messages: [String] { lock.withLock { recorded } }
    var isClosed: Bool { lock.withLock { closed } }
    var maximumConcurrentWrites: Int { lock.withLock { maximumWrites } }

    func send(_ message: String) async throws {
        lock.withLock {
            recorded.append(message)
            activeWrites += 1
            maximumWrites = max(maximumWrites, activeWrites)
        }
        defer { lock.withLock { activeWrites -= 1 } }
        if let writeGate { await writeGate.wait() }
        await Task.yield()
        if failWrites || isClosed { throw FakeError.offline }
    }

    func receive() async throws {
        try await withCheckedThrowingContinuation { completion in
            let alreadyClosed = lock.withLock {
                if closed { return true }
                receiver = completion
                return false
            }
            if alreadyClosed { completion.resume(throwing: FakeError.offline) }
        }
    }

    func ping() async throws {
        if failPings || isClosed { throw FakeError.offline }
        onPing()
    }

    func close() {
        let completion = lock.withLock {
            closed = true
            let pending = receiver
            receiver = nil
            return pending
        }
        completion?.resume(throwing: FakeError.offline)
    }
}
