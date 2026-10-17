import XCTest

final class VolumeMotionDeliveryTests: XCTestCase {
    private func step(_ session: String, _ activation: String, _ activationSequence: Int,
                      _ permit: String, sequence: Int = 1) -> VolumeBridgeMessage {
        VolumeBridgeMessage(kind: "motionStep", sessionID: session, permitID: permit,
            activationID: activation, activationSequence: activationSequence, sequence: sequence, direction: "up")
    }

    func testEndArrivingBeforeBeginPreventsLateActivation() {
        let gate = VolumeRelayGate(); let session = gate.begin(now: 0)
        gate.endMotion(session: session, activation: "ended", sequence: 1)
        XCTAssertFalse(gate.beginMotion(session: session, activation: "ended", sequence: 1, now: 0.1))
        XCTAssertFalse(gate.beginMotion(session: session, activation: "older", sequence: 0, now: 0.1))
        XCTAssertTrue(gate.beginMotion(session: session, activation: "fresh", sequence: 2, now: 0.1))
    }

    func testPauseRevokesAdmittedStepAtTheFinalWriteBoundary() throws {
        let gate = VolumeRelayGate(); let session = gate.begin(now: 0)
        XCTAssertTrue(gate.beginMotion(session: session, activation: "a", sequence: 1, now: 0))
        let permit = try XCTUnwrap(gate.issue(session: session, now: 0, activation: "a", activationSequence: 1))
        let deadline = try XCTUnwrap(gate.consume(step(session, "a", 1, permit), now: 0.1))
        gate.endMotion(session: session, activation: "a", sequence: 1)
        XCTAssertFalse(gate.valid(session: session, deadline: deadline, now: 0.2, activation: "a", activationSequence: 1))
        XCTAssertNil(gate.issue(session: session, now: 0.2, activation: "a", activationSequence: 1))
    }

    func testRecalibrationRejectsOldStepsHeartbeatsAndEnds() throws {
        let gate = VolumeRelayGate(); let session = gate.begin(now: 0)
        XCTAssertTrue(gate.beginMotion(session: session, activation: "a", sequence: 1, now: 0))
        let old = try XCTUnwrap(gate.issue(session: session, now: 0, activation: "a", activationSequence: 1))
        XCTAssertTrue(gate.beginMotion(session: session, activation: "b", sequence: 2, now: 0.1))
        gate.endMotion(session: session, activation: "a", sequence: 1)
        XCTAssertNil(gate.consume(step(session, "a", 1, old), now: 0.2))
        XCTAssertNil(gate.issue(session: session, now: 0.2, activation: "a", activationSequence: 1))
        XCTAssertNotNil(gate.issue(session: session, now: 0.2, activation: "b", activationSequence: 2))
    }

    func testMotionPermitCannotBecomeTapOrOtherActivation() throws {
        let gate = VolumeRelayGate(); let session = gate.begin(now: 0)
        XCTAssertTrue(gate.beginMotion(session: session, activation: "a", sequence: 1, now: 0))
        let permit = try XCTUnwrap(gate.issue(session: session, now: 0, activation: "a", activationSequence: 1))
        XCTAssertNil(gate.issue(session: session, now: 0.1))
        var forged = step(session, "a", 1, permit)
        forged.kind = "step"
        XCTAssertNil(gate.consume(forged, now: 0.1))
        forged = step(session, "b", 1, permit)
        XCTAssertNil(gate.consume(forged, now: 0.1))
        forged = step(session, "a", 2, permit)
        XCTAssertNil(gate.consume(forged, now: 0.1))
        XCTAssertNotNil(gate.consume(step(session, "a", 1, permit), now: 0.1))
    }

    func testMotionRateLimitAcrossActivationsAndRejectedDuplicateNeverPlaysLater() throws {
        let gate = VolumeRelayGate(); let session = gate.begin(now: 0)
        XCTAssertTrue(gate.beginMotion(session: session, activation: "a", sequence: 1, now: 0))
        let first = try XCTUnwrap(gate.issue(session: session, now: 0, activation: "a", activationSequence: 1))
        XCTAssertNotNil(gate.consume(step(session, "a", 1, first), now: 0.1))
        gate.endMotion(session: session, activation: "a", sequence: 1)
        XCTAssertTrue(gate.beginMotion(session: session, activation: "b", sequence: 2, now: 0.15))
        let second = try XCTUnwrap(gate.issue(session: session, now: 0.15, activation: "b", activationSequence: 2))
        let rejected = step(session, "b", 2, second, sequence: 2)
        XCTAssertNil(gate.consume(rejected, now: 0.3))
        XCTAssertNil(gate.consume(rejected, now: 0.4), "A rejected request cannot become a delayed replay")
        let fresh = try XCTUnwrap(gate.issue(session: session, now: 0.35, activation: "b", activationSequence: 2))
        XCTAssertNotNil(gate.consume(step(session, "b", 2, fresh, sequence: 3), now: 0.4))
    }

    func testHeartbeatCannotExtendAnAdmittedMotionCommand() throws {
        let gate = VolumeRelayGate(); let session = gate.begin(now: 0)
        XCTAssertTrue(gate.beginMotion(session: session, activation: "a", sequence: 1, now: 0))
        let permit = try XCTUnwrap(gate.issue(session: session, now: 0, activation: "a", activationSequence: 1))
        let deadline = try XCTUnwrap(gate.consume(step(session, "a", 1, permit), now: 0.1))
        XCTAssertNotNil(gate.issue(session: session, now: 0.4, activation: "a", activationSequence: 1))
        XCTAssertFalse(gate.valid(session: session, deadline: deadline, now: 0.5, activation: "a", activationSequence: 1))
    }

    func testDisconnectAndNewForegroundSessionRejectOldActivation() throws {
        let gate = VolumeRelayGate(); let session = gate.begin(now: 0)
        XCTAssertTrue(gate.beginMotion(session: session, activation: "a", sequence: 1, now: 0))
        let permit = try XCTUnwrap(gate.issue(session: session, now: 0, activation: "a", activationSequence: 1))
        let deadline = try XCTUnwrap(gate.consume(step(session, "a", 1, permit), now: 0.1))
        gate.cancel()
        let fresh = gate.begin(now: 0.2)
        XCTAssertFalse(gate.valid(session: session, deadline: deadline, now: 0.3, activation: "a", activationSequence: 1))
        XCTAssertFalse(gate.beginMotion(session: session, activation: "a", sequence: 1, now: 0.3))
        XCTAssertTrue(gate.beginMotion(session: fresh, activation: "b", sequence: 1, now: 0.3))
    }

    private func reply(_ activation: MotionActivation, permit: String = "p") -> VolumeBridgeMessage {
        VolumeBridgeMessage(kind: "motionBegin", sessionID: activation.sessionID, permitID: permit,
            activationID: activation.id, activationSequence: activation.sequence, status: "ready")
    }

    func testMotionStartClearsTapPermitAndRejectsLatePreactivationReply() {
        var taps = WatchVolumeAdmission()
        taps.connect(session: "s")
        taps.receivePermit("old", session: "s", requestStarted: 0)
        taps.discardPermit(at: 0.2)
        taps.receivePermit("late-old", session: "s", requestStarted: 0.1)
        XCTAssertNil(taps.takePermit(now: 0.3))
        XCTAssertEqual(taps.sessionID, "s")
        taps.receivePermit("fresh-after-end", session: "s", requestStarted: 0.4)
        XCTAssertEqual(taps.takePermit(now: 0.45), "fresh-after-end")
    }

    func testHeartbeatWaitsForBeginAndEndAcknowledgments() {
        var watch = WatchMotionAdmission()
        let activation = MotionActivation(sessionID: "s", generation: UUID(), sequence: 1)
        XCTAssertTrue(watch.canRefresh)
        watch.begin(activation)
        XCTAssertFalse(watch.canRefresh)
        watch.receive(reply(activation), for: activation, requestStarted: 0)
        XCTAssertTrue(watch.canRefresh)
        _ = watch.cancel()
        XCTAssertFalse(watch.canRefresh, "A tap heartbeat cannot overtake the remote end")
        watch.finishEnd(activation)
        XCTAssertTrue(watch.canRefresh)
    }

    func testNewBeginAcknowledgmentMakesOldEndBarrierUnnecessary() {
        var watch = WatchMotionAdmission()
        let old = MotionActivation(sessionID: "s", generation: UUID(), sequence: 1)
        let fresh = MotionActivation(sessionID: "s", generation: UUID(), sequence: 2)
        watch.begin(old); _ = watch.cancel(); watch.begin(fresh)
        watch.receive(reply(fresh), for: fresh, requestStarted: 0.1)
        XCTAssertTrue(watch.canRefresh)
        watch.finishEnd(old)
        XCTAssertTrue(watch.isCurrent(fresh))
        XCTAssertTrue(watch.canRefresh)
    }

    func testForegroundResetDiscardsOldEndBarrierAndLateReplies() {
        var watch = WatchMotionAdmission()
        let old = MotionActivation(sessionID: "s", generation: UUID(), sequence: 1)
        watch.begin(old); _ = watch.cancel(); watch.reset()
        let fresh = MotionActivation(sessionID: "new", generation: UUID(), sequence: 1)
        watch.begin(fresh)
        watch.finishEnd(old)
        watch.receive(reply(old), for: old, requestStarted: 0.1)
        XCTAssertFalse(watch.canRefresh)
        watch.receive(reply(fresh), for: fresh, requestStarted: 0.2)
        XCTAssertTrue(watch.canRefresh)
    }

    func testDelayedBeginReplyAfterPauseCannotArmOrSend() {
        var watch = WatchMotionAdmission()
        let activation = MotionActivation(sessionID: "s", generation: UUID(), sequence: 1)
        watch.begin(activation)
        XCTAssertFalse(watch.ready)
        _ = watch.cancel()
        watch.receive(reply(activation), for: activation, requestStarted: 0)
        XCTAssertFalse(watch.ready)
        XCTAssertNil(watch.take(for: activation.generation, timestamp: 0.1, now: 0.1))
    }

    func testLateCallbackCannotEnterNewCalibrationGeneration() {
        var watch = WatchMotionAdmission()
        let old = MotionActivation(sessionID: "s", generation: UUID(), sequence: 1)
        let fresh = MotionActivation(sessionID: "s", generation: UUID(), sequence: 2)
        watch.begin(old); _ = watch.cancel(); watch.begin(fresh)
        watch.receive(reply(old), for: old, requestStarted: 0.1)
        XCTAssertFalse(watch.ready)
        watch.receive(reply(fresh), for: fresh, requestStarted: 0.2)
        XCTAssertTrue(watch.ready)
        XCTAssertNil(watch.take(for: old.generation, timestamp: 0.3, now: 0.3))
        XCTAssertNotNil(watch.take(for: fresh.generation, timestamp: 0.3, now: 0.3))
    }

    func testStaleIntentIsNotReplayedWithANewerPermit() {
        var watch = WatchMotionAdmission()
        let activation = MotionActivation(sessionID: "s", generation: UUID(), sequence: 1)
        watch.begin(activation)
        watch.receive(reply(activation), for: activation, requestStarted: 0.3)
        XCTAssertNil(watch.take(for: activation.generation, timestamp: 0, now: 0.4))
        XCTAssertNotNil(watch.take(for: activation.generation, timestamp: 0.4, now: 0.4))
        XCTAssertNil(watch.take(for: activation.generation, timestamp: 0.41, now: 0.41), "No permit reuse")
    }

    func testLocalCancellationInvalidatesRequestBeforeTransportCall() {
        var watch = WatchMotionAdmission()
        let activation = MotionActivation(sessionID: "s", generation: UUID(), sequence: 1)
        watch.begin(activation)
        watch.receive(reply(activation), for: activation, requestStarted: 0)
        XCTAssertNotNil(watch.take(for: activation.generation, timestamp: 0.1, now: 0.1))
        _ = watch.cancel()
        XCTAssertFalse(watch.valid(activation, generation: activation.generation, timestamp: 0.1, now: 0.11))
    }
}
