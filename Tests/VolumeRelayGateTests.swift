import XCTest

final class VolumeRelayGateTests: XCTestCase {
    private func step(_ session: String, _ permit: String, sequence: Int = 1,
                      direction: String = "up") -> VolumeBridgeMessage {
        VolumeBridgeMessage(kind: "step", sessionID: session, permitID: permit,
                            sequence: sequence, direction: direction)
    }

    func testFreshPermitCanBeConsumedOnlyOnce() throws {
        let gate = VolumeRelayGate()
        let session = gate.begin(now: 10)
        let permit = try XCTUnwrap(gate.issue(session: session, now: 10))
        let message = step(session, permit)
        XCTAssertEqual(gate.consume(message, now: 10.1), 10.5)
        XCTAssertNil(gate.consume(message, now: 10.3))
    }

    func testHeartbeatCannotExtendOldCommandDeadline() throws {
        let gate = VolumeRelayGate()
        let session = gate.begin(now: 1)
        let permit = try XCTUnwrap(gate.issue(session: session, now: 1))
        let deadline = try XCTUnwrap(gate.consume(step(session, permit), now: 1.1))
        XCTAssertNotNil(gate.issue(session: session, now: 1.4))
        XCTAssertFalse(gate.valid(session: session, deadline: deadline, now: 1.5))
    }

    func testExpiryAndLeaseDoNotReopenOnDelayedHeartbeat() throws {
        let gate = VolumeRelayGate()
        let session = gate.begin(now: 1)
        let permit = try XCTUnwrap(gate.issue(session: session, now: 1))
        XCTAssertNil(gate.consume(step(session, permit), now: 1.5))
        XCTAssertNil(gate.issue(session: session, now: 3))
        XCTAssertFalse(gate.hasLease(now: 3))
    }

    func testCancelDisconnectAndNewSessionInvalidateAdmittedWork() throws {
        for newSession in [false, true] {
            let gate = VolumeRelayGate()
            let session = gate.begin(now: 0)
            let permit = try XCTUnwrap(gate.issue(session: session, now: 0))
            let deadline = try XCTUnwrap(gate.consume(step(session, permit), now: 0.1))
            if newSession { _ = gate.begin(now: 0.2) } else { gate.cancel() }
            XCTAssertFalse(gate.valid(session: session, deadline: deadline, now: 0.3))
            XCTAssertNil(gate.issue(session: session, now: 0.3))
        }
    }

    func testLateEndCannotCancelNewSession() throws {
        let gate = VolumeRelayGate()
        let old = gate.begin(now: 0)
        let fresh = gate.begin(now: 0.1)
        gate.cancel(session: old)
        XCTAssertNotNil(gate.issue(session: fresh, now: 0.2))
    }

    func testRejectsReorderedDuplicateAndArbitraryCommands() throws {
        let gate = VolumeRelayGate()
        let session = gate.begin(now: 0)
        let first = try XCTUnwrap(gate.issue(session: session, now: 0))
        let second = try XCTUnwrap(gate.issue(session: session, now: 0.1))
        let message = step(session, first, sequence: 2)
        XCTAssertNotNil(gate.consume(message, now: 0.11))
        XCTAssertNil(gate.consume(step(session, second), now: 0.3))
        var duplicate = step(session, second, sequence: 3)
        duplicate.requestID = message.requestID
        XCTAssertNil(gate.consume(duplicate, now: 0.3))
        XCTAssertNil(gate.consume(step(session, second, sequence: 3, direction: "KEY_POWER"), now: 0.3))
    }

    func testRateLimitAndReversalDoNotAccumulateCommands() throws {
        let gate = VolumeRelayGate()
        let session = gate.begin(now: 0)
        let a = try XCTUnwrap(gate.issue(session: session, now: 0))
        let b = try XCTUnwrap(gate.issue(session: session, now: 0.01))
        XCTAssertNotNil(gate.consume(step(session, a), now: 0.02))
        XCTAssertNil(gate.consume(step(session, b, sequence: 2, direction: "down"), now: 0.03))
        XCTAssertNotNil(gate.consume(step(session, b, sequence: 3, direction: "down"), now: 0.2))
    }

    func testPermitStorageIsBounded() {
        let gate = VolumeRelayGate()
        let session = gate.begin(now: 0)
        for _ in 0..<4 { XCTAssertNotNil(gate.issue(session: session, now: 0)) }
        XCTAssertNil(gate.issue(session: session, now: 0))
        XCTAssertNotNil(gate.issue(session: session, now: 0.5))
    }
}

final class WatchVolumeAdmissionTests: XCTestCase {
    func testHeartbeatLatencyGapDoesNotDisconnectControls() {
        var admission = WatchVolumeAdmission()
        admission.connect(session: "live")
        admission.receivePermit("first", session: "live", requestStarted: 0)
        // Connection stays ready even when a cached permit truly expires.
        XCTAssertNil(admission.takePermit(now: 0.6))
        XCTAssertEqual(admission.sessionID, "live")
        admission.receivePermit("next", session: "live", requestStarted: 0.6)
        XCTAssertEqual(admission.takePermit(now: 0.7), "next")
        XCTAssertEqual(admission.sessionID, "live")
    }

    func testLateReadyReplyDoesNotAuthorizeAnExpiredTap() {
        var admission = WatchVolumeAdmission()
        admission.connect(session: "live")
        admission.receivePermit("late", session: "live", requestStarted: 10)
        // A cached permit can still be valid, but it cannot refresh an old tap.
        XCTAssertEqual(admission.takePermit(now: 10.3), "late")
        XCTAssertFalse(WatchVolumeAdmission.freshTap(started: 10, now: 10.3))
        // A later heartbeat cannot make the original tap fresh again.
        admission.receivePermit("fresh", session: "live", requestStarted: 10.3)
        XCTAssertFalse(WatchVolumeAdmission.freshTap(started: 10, now: 10.4))
    }

    func testMeasured239msReplyLeavesPermitReadyForTheNextTap() {
        var admission = WatchVolumeAdmission()
        admission.connect(session: "live")
        admission.receivePermit("first", session: "live", requestStarted: 0)
        let delay = VolumeBridgeTiming.refreshDelay(requestStarted: 0, now: 0.239)
        XCTAssertEqual(delay, 0, accuracy: 0.000001)
        // The next heartbeat starts at 239 ms, not at 439 ms. Before its reply,
        // a tap at 400 ms can use the existing permit with no extra request.
        XCTAssertEqual(admission.takePermit(now: 0.400), "first")
        admission.receivePermit("second", session: "live", requestStarted: 0.239)
        XCTAssertEqual(admission.takePermit(now: 0.600), "second")
    }

    func testRefreshCadenceDoesNotExceedFiveRequestsPerSecondOnFastLinks() {
        XCTAssertEqual(VolumeBridgeTiming.refreshDelay(requestStarted: 1, now: 1.05), 0.15, accuracy: 0.000001)
        XCTAssertEqual(VolumeBridgeTiming.refreshDelay(requestStarted: 1, now: 1.3), 0)
    }

    func testCachedPermitExpiresAtConservativeRelayLifetime() {
        var admission = WatchVolumeAdmission()
        admission.connect(session: "live")
        admission.receivePermit("permit", session: "live", requestStarted: 0)
        XCTAssertNil(admission.takePermit(now: 0.5))
        XCTAssertFalse(WatchVolumeAdmission.freshTap(started: 0, now: 0.3))
    }

    func testDelayedOlderHeartbeatCannotReplaceNewerPermit() {
        var admission = WatchVolumeAdmission()
        admission.connect(session: "live")
        admission.receivePermit("newer", session: "live", requestStarted: 0.2)
        admission.receivePermit("older", session: "live", requestStarted: 0.1)
        XCTAssertEqual(admission.takePermit(now: 0.3), "newer")
        // Nor can a duplicate reply reintroduce the consumed permit.
        admission.receivePermit("newer", session: "live", requestStarted: 0.2)
        XCTAssertNil(admission.takePermit(now: 0.31))
    }

    func testEndRejectsLatePermitAndNewSessionRejectsOldReply() {
        var admission = WatchVolumeAdmission()
        admission.connect(session: "old")
        admission.end()
        admission.receivePermit("stale", session: "old", requestStarted: 0)
        XCTAssertNil(admission.sessionID)
        XCTAssertNil(admission.takePermit(now: 0.1))
        admission.connect(session: "new")
        admission.receivePermit("stale", session: "old", requestStarted: 0.1)
        XCTAssertNil(admission.takePermit(now: 0.2))
        XCTAssertEqual(admission.sessionID, "new")
    }

    func testPermitIsSingleUseAndTapDeadlineIsStrict() {
        var admission = WatchVolumeAdmission()
        admission.connect(session: "live")
        admission.receivePermit("permit", session: "live", requestStarted: 0)
        XCTAssertEqual(admission.takePermit(now: 0.1), "permit")
        XCTAssertNil(admission.takePermit(now: 0.11))
        XCTAssertTrue(WatchVolumeAdmission.freshTap(started: 1, now: 1.24))
        XCTAssertFalse(WatchVolumeAdmission.freshTap(started: 1, now: 1.25))
    }
}
