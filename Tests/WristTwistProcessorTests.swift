import XCTest

final class WristTwistProcessorTests: XCTestCase {
    private let x = MotionVector(x: 1, y: 0, z: 0)
    private let y = MotionVector(x: 0, y: 1, z: 0)
    private let z = MotionVector(x: 0, y: 0, z: 1)

    private func sample(_ time: Double, degrees: Double = 0, axis: MotionVector? = nil,
                        base: MotionQuaternion = .identity, sign: Double = 1,
                        speed: Double = 0, acceleration: Double = 0) -> MotionSample {
        MotionSample(timestamp: time,
                     attitude: (base * .rotation(axis: axis ?? x, radians: degrees * .pi / 180)).scaled(sign),
                     rotationRate: MotionVector(x: speed, y: 0, z: 0),
                     gravity: MotionVector(x: 0, y: 0, z: -1),
                     userAcceleration: MotionVector(x: acceleration, y: 0, z: 0))
    }

    private func ready(_ config: GestureConfiguration? = nil,
                       base: MotionQuaternion = .identity) -> (WristTwistProcessor, UUID) {
        var config = config ?? GestureConfiguration()
        config.calibrationDuration = 0.1
        config.filterTimeConstant = 0
        var processor = WristTwistProcessor()
        let id = UUID()
        processor.begin(generation: id, configuration: config, now: 0)
        for index in 0...6 {
            let t = Double(index) * 0.02
            XCTAssertNil(processor.handle(sample(t, base: base), generation: id, now: t))
        }
        XCTAssertEqual(processor.phase, .active)
        return (processor, id)
    }

    func testIdleAndUnrelatedGenerationNeverEmit() {
        var processor = WristTwistProcessor()
        let sample = sample(0, degrees: 30)
        XCTAssertNil(processor.handle(sample, generation: UUID(), now: 0))
        let (readyProcessor, id) = ready()
        processor = readyProcessor
        XCTAssertNil(processor.handle(self.sample(0.2, degrees: 30), generation: UUID(), now: 0.2))
        XCTAssertNotNil(processor.handle(self.sample(0.2, degrees: 30), generation: id, now: 0.2))
    }

    func testQuietJitterAndStationaryTiltDoNotRepeatSteps() {
        var (processor, id) = ready()
        for index in 7...50 {
            let t = Double(index) * 0.02
            XCTAssertNil(processor.handle(sample(t, degrees: index.isMultiple(of: 2) ? 2 : -2), generation: id, now: t))
        }
        XCTAssertNil(processor.handle(sample(1.02, degrees: 8), generation: id, now: 1.02))
        XCTAssertNil(processor.handle(sample(1.04, degrees: 15), generation: id, now: 1.04))
        XCTAssertEqual(processor.handle(sample(1.06, degrees: 20), generation: id, now: 1.06)?.direction, .up)
        for index in 54...100 {
            let t = Double(index) * 0.02
            XCTAssertNil(processor.handle(sample(t, degrees: 20), generation: id, now: t))
        }
    }

    func testBothDirectionsAndProposedWristCrownMapping() {
        for wrist in [GestureConfiguration.Wrist.left, .right] {
            for crown in [GestureConfiguration.Crown.left, .right] {
                for inverted in [false, true] {
                    var config = GestureConfiguration()
                    config.wrist = wrist; config.crown = crown; config.inverted = inverted
                    var (processor, id) = ready(config)
                    let intent = processor.handle(sample(0.2, degrees: 20, axis: config.twistAxis), generation: id, now: 0.2)
                    XCTAssertEqual(intent?.direction, inverted ? .down : .up)
                    XCTAssertEqual(intent?.generation, id)
                    XCTAssertEqual(intent?.timestamp, 0.2)
                }
            }
        }
        var (processor, id) = ready()
        XCTAssertEqual(processor.handle(sample(0.2, degrees: -20), generation: id, now: 0.2)?.direction, .down)
    }

    func testDifferentPosturesAndAxisSelectionPreserveRelativeTwist() {
        for base in [MotionQuaternion.identity, .rotation(axis: z, radians: 1.3), .rotation(axis: y, radians: -1.1)] {
            for axis in [GestureConfiguration.Axis.x, .y] {
                var config = GestureConfiguration(); config.axis = axis
                var (processor, id) = ready(config, base: base)
                XCTAssertEqual(processor.handle(sample(0.2, degrees: 20, axis: axis.vector, base: base), generation: id, now: 0.2)?.direction, .up)
            }
        }
    }

    func testQuaternionSignFlipHasNoEffect() {
        var (processor, id) = ready()
        XCTAssertNil(processor.handle(sample(0.14, sign: -1), generation: id, now: 0.14))
        XCTAssertEqual(processor.handle(sample(0.2, degrees: 20, sign: -1), generation: id, now: 0.2)?.direction, .up)
        XCTAssertNil(processor.handle(sample(0.22, degrees: 20, sign: 1), generation: id, now: 0.22))
    }

    func testReversalRequiresHysteresisAndAnotherDetent() {
        var (processor, id) = ready()
        XCTAssertEqual(processor.handle(sample(0.2, degrees: 20), generation: id, now: 0.2)?.direction, .up)
        for (t, angle) in [(0.3, 19.0), (0.4, 21.0), (0.5, 19.0), (0.6, 17.0), (0.7, 10.0)] {
            XCTAssertNil(processor.handle(sample(t, degrees: angle), generation: id, now: t))
        }
        XCTAssertEqual(processor.handle(sample(0.8, degrees: 5), generation: id, now: 0.8)?.direction, .down)
    }

    func testRateLimitedDisplacementIsConsumedNotReplayed() {
        var (processor, id) = ready()
        XCTAssertNotNil(processor.handle(sample(0.2, degrees: 20), generation: id, now: 0.2))
        XCTAssertNil(processor.handle(sample(0.24, degrees: 35), generation: id, now: 0.24))
        for (t, angle) in [(0.34, 35.0), (0.44, 35.0), (0.54, 35.0)] {
            XCTAssertNil(processor.handle(sample(t, degrees: angle), generation: id, now: t))
        }
        XCTAssertNotNil(processor.handle(sample(0.6, degrees: 50), generation: id, now: 0.6))
    }

    func testWraparoundDoesNotBecomeAFalseReversal() {
        var config = GestureConfiguration()
        config.maximumTwistDegrees = 400; config.maximumSpeedDegrees = 2000; config.commandInterval = 0
        var (processor, id) = ready(config)
        var directions: [TwistIntent.Direction] = []
        for (t, angle) in [(0.22, 80.0), (0.32, 160.0), (0.42, 179.0), (0.52, -179.0), (0.62, -150.0)] {
            if let intent = processor.handle(sample(t, degrees: angle), generation: id, now: t) { directions.append(intent.direction) }
        }
        XCTAssertEqual(directions, [.up, .up, .up, .up])
        XCTAssertEqual(processor.phase, .active)
        XCTAssertEqual(processor.angleDegrees, 210, accuracy: 0.000001)
    }

    func testLimitsRequireExplicitReleaseAndRecalibration() {
        var (processor, id) = ready()
        XCTAssertNil(processor.handle(sample(0.22, degrees: 36, axis: y), generation: id, now: 0.22))
        guard case .recenter = processor.phase else { return XCTFail("Expected off-axis stop") }
        XCTAssertNil(processor.handle(sample(0.24, degrees: 20), generation: id, now: 0.24))
        (processor, _) = ready()
        // A different activation ID cannot restart a stopped processor.
        processor.stop()
        XCTAssertNil(processor.handle(sample(0.2, degrees: 20), generation: id, now: 0.2))
        XCTAssertEqual(processor.phase, .idle)
        (processor, id) = ready()
        XCTAssertNotNil(processor.handle(sample(0.22, degrees: 60), generation: id, now: 0.22))
        XCTAssertNil(processor.handle(sample(0.24, degrees: 71), generation: id, now: 0.24))
        guard case .recenter = processor.phase else { return XCTFail("Expected range stop") }
    }

    func testCalibrationRejectsMovementAndTimesOut() {
        var processor = WristTwistProcessor()
        let id = UUID()
        var config = GestureConfiguration(); config.calibrationTimeout = 0.5
        processor.begin(generation: id, configuration: config, now: 0)
        for index in 0..<25 {
            let t = Double(index) * 0.02
            XCTAssertNil(processor.handle(sample(t, speed: 1, acceleration: 0.3), generation: id, now: t))
        }
        XCTAssertEqual(processor.phase, .calibrating)
        processor.tick(now: 0.5, generation: id)
        guard case .recenter = processor.phase else { return XCTFail("Expected calibration timeout") }
    }

    func testCalibrationSpreadResetsQuietWindow() {
        var processor = WristTwistProcessor(); let id = UUID()
        var config = GestureConfiguration(); config.calibrationDuration = 0.1
        processor.begin(generation: id, configuration: config, now: 0)
        for index in 0...10 {
            let t = Double(index) * 0.02
            _ = processor.handle(sample(t, degrees: Double(index) * 2), generation: id, now: t)
        }
        XCTAssertEqual(processor.phase, .calibrating)
    }

    func testStaleGapInvalidAndOutOfOrderSamples() {
        var (processor, id) = ready()
        XCTAssertNil(processor.handle(sample(0.1, degrees: 25), generation: id, now: 0.13))
        XCTAssertEqual(processor.phase, .active)
        XCTAssertNil(processor.handle(sample(0.4, degrees: 25), generation: id, now: 0.4))
        guard case .recenter = processor.phase else { return XCTFail("Expected gap stop") }
        (processor, id) = ready()
        XCTAssertNil(processor.handle(sample(0.2, degrees: 25), generation: id, now: 0.5))
        guard case .recenter = processor.phase else { return XCTFail("Expected stale stop") }
        (processor, id) = ready()
        let invalid = MotionSample(timestamp: 0.2, attitude: .init(x: .nan, y: 0, z: 0, w: 1),
                                   rotationRate: .zero, gravity: .init(x: 0, y: 0, z: -1), userAcceleration: .zero)
        XCTAssertNil(processor.handle(invalid, generation: id, now: 0.2))
        guard case .recenter = processor.phase else { return XCTFail("Expected invalid stop") }
    }

    func testClutchRecalibratesAtNewPoseAndIgnoresOldGeneration() {
        var (processor, old) = ready()
        _ = processor.handle(sample(0.2, degrees: 20), generation: old, now: 0.2)
        processor.stop()
        let fresh = UUID(); var config = GestureConfiguration(); config.calibrationDuration = 0.1
        let base = MotionQuaternion.rotation(axis: x, radians: 0.5)
        processor.begin(generation: fresh, configuration: config, now: 1)
        XCTAssertNil(processor.handle(sample(1, degrees: 30), generation: old, now: 1))
        for index in 0...6 {
            let t = 1 + Double(index) * 0.02
            XCTAssertNil(processor.handle(sample(t, base: base), generation: fresh, now: t))
        }
        XCTAssertEqual(processor.phase, .active)
        XCTAssertEqual(processor.angleDegrees, 0)
        XCTAssertNil(processor.handle(sample(1.14, base: base), generation: fresh, now: 1.14))
    }

    func testCachedPreactivationSampleDoesNotAbortNewCalibration() {
        var processor = WristTwistProcessor(); let id = UUID()
        processor.begin(generation: id, configuration: GestureConfiguration(), now: 1)
        XCTAssertNil(processor.handle(sample(0.99), generation: id, now: 1.01))
        XCTAssertEqual(processor.phase, .calibrating)
        XCTAssertEqual(processor.generation, id)
    }

    func testFirstDetentBoundaryIsDeadZonePlusDetent() {
        var (processor, id) = ready()
        XCTAssertNil(processor.handle(sample(0.14, degrees: 5), generation: id, now: 0.14))
        XCTAssertNil(processor.handle(sample(0.16, degrees: 16.999), generation: id, now: 0.16))
        XCTAssertEqual(processor.handle(sample(0.18, degrees: 17), generation: id, now: 0.18)?.direction, .up)
    }

    func testMaximumHoldAndMissingSampleWatchdogDisarm() {
        var config = GestureConfiguration(); config.maximumHold = 0.3
        var (processor, id) = ready(config)
        processor.tick(now: 0.3, generation: id)
        XCTAssertNil(processor.generation)
        (processor, id) = ready()
        processor.tick(now: 0.4, generation: id)
        XCTAssertNil(processor.generation)
    }

    func testContinuousForegroundConfigurationDoesNotRequireTenSecondRearm() {
        var config = GestureConfiguration()
        config.maximumHold = .infinity
        var (processor, id) = ready(config)
        for index in 7...601 {
            let t = Double(index) * 0.02
            XCTAssertNil(processor.handle(sample(t), generation: id, now: t))
        }
        XCTAssertEqual(processor.phase, .active)
        processor.stop()
        XCTAssertNil(processor.handle(sample(12.04, degrees: 20), generation: id, now: 12.04))
    }

    func testVariableCadenceFilteringStaysInDeadZoneForSmallNoise() {
        var processor = WristTwistProcessor(); let id = UUID()
        var config = GestureConfiguration(); config.calibrationDuration = 0.1
        processor.begin(generation: id, configuration: config, now: 0)
        for t in [0.0, 0.03, 0.06, 0.11, 0.15, 0.18, 0.22, 0.28] {
            XCTAssertNil(processor.handle(sample(t, degrees: t > 0.11 ? 2 : 0), generation: id, now: t))
        }
        XCTAssertEqual(processor.phase, .active)
    }
}
