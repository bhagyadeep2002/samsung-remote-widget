import Foundation
import XCTest

final class HeldFingerVolumeSessionTests: XCTestCase {
    private func ready(_ id: UUID) -> HeldFingerVolumeSession {
        var session = HeldFingerVolumeSession()
        session.begin(generation: id, now: 0)
        XCTAssertTrue(session.linkReady(generation: id, now: 0.1))
        return session
    }

    func testPreparingCannotRecognizeAndReleasedHoldCannotBeStartedByLateReply() {
        let id = UUID()
        var session = HeldFingerVolumeSession()
        session.begin(generation: id, now: 0)
        XCTAssertEqual(session.tick(generation: id, now: 3), .none)
        XCTAssertNil(session.complete(.up, generation: id, sampleTimestamp: 3, now: 3))
        session.cancel()
        XCTAssertFalse(session.linkReady(generation: id, now: 3.1))
        XCTAssertFalse(session.isHeld)
    }

    func testDecisionStartsOnceWhileStillHeldAndNotOnRelease() {
        let id = UUID()
        var session = ready(id)
        XCTAssertEqual(session.tick(generation: id, now: 2.59), .none)
        XCTAssertEqual(session.tick(generation: id, now: 2.6), .decide)
        XCTAssertTrue(session.isHeld)
        XCTAssertEqual(session.phase, .waitingForRelease)
        XCTAssertEqual(session.tick(generation: id, now: 2.7), .none)
        session.cancel()
        XCTAssertNil(session.complete(.up, generation: id, sampleTimestamp: 2.7, now: 2.7))
    }

    func testEachDirectionEmitsExactlyOneIntentUntilRelease() throws {
        for decision in [FingerGestureClassifier.Decision.up, .down] {
            let id = UUID()
            var session = ready(id)
            XCTAssertEqual(session.tick(generation: id, now: 2.6), .decide)
            let intent = try XCTUnwrap(session.complete(decision, generation: id, sampleTimestamp: 2.59, now: 2.62))
            XCTAssertEqual(intent.direction.rawValue, decision.rawValue)
            XCTAssertEqual(intent.generation, id)
            XCTAssertEqual(intent.timestamp, 2.6)
            XCTAssertNil(session.complete(decision, generation: id, sampleTimestamp: 2.65, now: 2.66))
            XCTAssertEqual(session.tick(generation: id, now: 3), .none)
            session.cancel()
            XCTAssertFalse(session.isHeld)
        }
    }

    func testStillAndUnsureConsumeDecisionWithoutCommandOrLaterReplay() {
        for decision in [FingerGestureClassifier.Decision.still, .unsure] {
            let id = UUID()
            var session = ready(id)
            XCTAssertEqual(session.tick(generation: id, now: 2.6), .decide)
            XCTAssertNil(session.complete(decision, generation: id, sampleTimestamp: 2.59, now: 2.62))
            XCTAssertNil(session.complete(.up, generation: id, sampleTimestamp: 2.63, now: 2.64))
            XCTAssertTrue(session.isHeld)
        }
    }

    func testStaleFutureOrInvalidSamplesCannotBeRetriedWithFreshSamples() {
        for timestamp in [2.0, 2.8, .nan] {
            let id = UUID()
            var session = ready(id)
            _ = session.tick(generation: id, now: 2.6)
            XCTAssertNil(session.complete(.up, generation: id, sampleTimestamp: timestamp, now: 2.62))
            XCTAssertNil(session.complete(.up, generation: id, sampleTimestamp: 2.64, now: 2.65))
        }
    }

    func testDelayedRecognitionAndStalledTimersCannotSendOldMovement() {
        let id = UUID()
        var session = ready(id)
        _ = session.tick(generation: id, now: 2.6)
        XCTAssertNil(session.complete(.up, generation: id, sampleTimestamp: 2.86, now: 2.86))
        session = ready(id)
        XCTAssertEqual(session.tick(generation: id, now: 3), .expired)
        XCTAssertFalse(session.isHeld)
        XCTAssertNil(session.complete(.up, generation: id, sampleTimestamp: 3, now: 3))
    }

    func testMaximumHoldExpiresIncludingWhileWaitingForLinkOrRelease() {
        let id = UUID()
        var session = HeldFingerVolumeSession()
        session.begin(generation: id, now: 0)
        XCTAssertEqual(session.tick(generation: id, now: 10), .expired)
        XCTAssertFalse(session.linkReady(generation: id, now: 10))
        session = ready(id)
        _ = session.tick(generation: id, now: 2.6)
        _ = session.complete(.still, generation: id, sampleTimestamp: 2.6, now: 2.6)
        XCTAssertEqual(session.tick(generation: id, now: 10), .expired)
        XCTAssertFalse(session.isHeld)
    }

    func testNewHoldRejectsOldTimerClassifierAndConnectionReply() {
        let old = UUID(), fresh = UUID()
        var session = ready(old)
        _ = session.tick(generation: old, now: 2.6)
        session.cancel()
        session.begin(generation: fresh, now: 3)
        XCTAssertEqual(session.tick(generation: old, now: 5.6), .none)
        XCTAssertFalse(session.linkReady(generation: old, now: 3.1))
        XCTAssertNil(session.complete(.up, generation: old, sampleTimestamp: 3.1, now: 3.1))
        XCTAssertTrue(session.linkReady(generation: fresh, now: 3.1))
        XCTAssertEqual(session.tick(generation: fresh, now: 5.6), .decide)
        XCTAssertNotNil(session.complete(.down, generation: fresh, sampleTimestamp: 5.6, now: 5.6))
    }

    func testBusyOrMissingPermitDropsRecognizedIntentInsteadOfQueuing() throws {
        let id = UUID()
        var held = ready(id)
        var watch = WatchMotionAdmission()
        let activation = MotionActivation(sessionID: "s", generation: id, sequence: 1)
        watch.begin(activation)
        let reply = VolumeBridgeMessage(kind: "motionBegin", sessionID: "s", permitID: "old",
            activationID: activation.id, activationSequence: 1, status: "ready")
        watch.receive(reply, for: activation, requestStarted: 0)
        _ = held.tick(generation: id, now: 2.6)
        let intent = try XCTUnwrap(held.complete(.up, generation: id, sampleTimestamp: 2.6, now: 2.6))
        XCTAssertNil(watch.take(for: id, timestamp: intent.timestamp, now: 2.6))
        watch.receive(reply, for: activation, requestStarted: 2.7)
        XCTAssertNil(held.complete(.up, generation: id, sampleTimestamp: 2.7, now: 2.7))
        XCTAssertEqual(held.tick(generation: id, now: 2.7), .none)
    }

    func testReleaseRevokesFreshAdmittedFingerStepAtFinalWriteBoundary() throws {
        let id = UUID(), gate = VolumeRelayGate()
        let sessionID = gate.begin(now: 0)
        let activation = MotionActivation(sessionID: sessionID, generation: id, sequence: 1)
        XCTAssertTrue(gate.beginMotion(session: sessionID, activation: activation.id, sequence: 1, now: 0))
        _ = gate.issue(session: sessionID, now: 1, activation: activation.id, activationSequence: 1)
        let permit = try XCTUnwrap(gate.issue(session: sessionID, now: 2.4, activation: activation.id, activationSequence: 1))
        var held = ready(id)
        var watch = WatchMotionAdmission()
        watch.begin(activation)
        watch.receive(VolumeBridgeMessage(kind: "heartbeat", sessionID: sessionID, permitID: permit,
            activationID: activation.id, activationSequence: 1, status: "ready"), for: activation, requestStarted: 2.4)
        _ = held.tick(generation: id, now: 2.6)
        let intent = try XCTUnwrap(held.complete(.up, generation: id, sampleTimestamp: 2.6, now: 2.61))
        let (_, token) = try XCTUnwrap(watch.take(for: id, timestamp: intent.timestamp, now: 2.61))
        let step = VolumeBridgeMessage(kind: "motionStep", sessionID: sessionID, permitID: token,
            activationID: activation.id, activationSequence: 1, sequence: 1, direction: intent.direction.rawValue)
        let deadline = try XCTUnwrap(gate.consume(step, now: 2.62))
        held.cancel() // local release before the transport writes
        _ = watch.cancel()
        gate.endMotion(session: sessionID, activation: activation.id, sequence: 1)
        XCTAssertFalse(held.isHeld)
        XCTAssertFalse(watch.valid(activation, generation: id, timestamp: intent.timestamp, now: 2.63))
        XCTAssertFalse(gate.valid(session: sessionID, deadline: deadline, now: 2.63, activation: activation.id, activationSequence: 1))
    }
}
