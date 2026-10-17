import Foundation
import XCTest

final class FingerGestureClassifierTests: XCTestCase {
    private func trial(label: FingerGestureRecording.Label = .up, offset: Double = 0,
                       wrist: String = "left", crown: String = "right",
                       acquisition: FingerCaptureAcquisition = .rawAccelerometerWithDeviceMotionRotation) -> FingerGestureRecording {
        let points = (0...300).map { i -> (FingerGestureRecording.Point, FingerGestureRecording.Point) in
            let t = Double(i)/100
            let envelope = exp(-pow((t-1.5)/0.25, 2))
            let a = FingerGestureRecording.Point(time: t,
                x: 0.03*sin(2 * .pi * 8*t)*envelope + offset,
                y: 0.02*cos(2 * .pi * 12*t)*envelope + offset,
                z: -1 + 0.02*sin(2 * .pi * 12*t)*envelope + offset)
            let g = FingerGestureRecording.Point(time: t,
                x: 0.35*sin(2 * .pi * 8*t)*envelope + offset,
                y: 0.08*cos(2 * .pi * 8*t)*envelope + offset,
                z: 0.04*sin(2 * .pi * 5*t)*envelope + offset)
            return (a,g)
        }
        return FingerGestureRecording(version: 2, id: UUID(), label: label, capturedAt: Date(),
            wrist: wrist, crown: crown, device: "Synthetic", systemVersion: "27", requestedInterval: 0.01,
            duration: 3, accelerometer: points.map(\.0), gyroscope: points.map(\.1), acquisition: acquisition)
    }

    func testFeaturesMatchIndependentPythonReference() throws {
        // Filled by the reference analysis pipeline for the deterministic waveform
        // above; this checks resampling, Gaussian boundary handling, peak selection,
        // quantiles and correlations, independently of the frozen training labels.
        let expected: [Double] = [0.011873785718319112, -0.0151996022865534, 0.015199602286553414, -0.029512744821844329, 0.029512744821844291, 0.0059522110232784085, 0.0079158637156635115, -0.010075139763491177, 0.0116358685732444, -0.019340776865922369, 0.019999999081286628, 0.0058635625877855617, 0.0079157815735792971, -0.011052912974488672, 0.011052912974488984, -0.019833194074366567, 0.019833194074366678, 0.0058636680269391816, 0.13852732490516384, -0.17732858572637278, 0.17732858572637319, -0.34431534341786835, 0.34431534341786824, 0.069442375912631638, 0.031663248842602951, -0.044317803774732323, 0.042619080484129775, -0.074926683539814964, 0.079999999999999974, 0.015872668447830789, 0.015831856094087497, -0.021436848247452182, 0.021436848247452116, -0.038431577566092931, 0.038431577566092931, 0.005016522719050019, 6.535980891597741e-06, 0.007125550665891719, 8.9002161096598266e-06, 1.9239021853271579e-05, -0.062359277313578335, 1.3068939316299105e-05]
        let actual = try XCTUnwrap(FingerGestureClassifier.features(trial()))
        XCTAssertEqual(actual.count, expected.count)
        for (a,e) in zip(actual, expected) { XCTAssertEqual(a, e, accuracy: 1e-8) }
    }

    func testStaticPoseAndGyroBiasDoNotBecomeClassFeatures() throws {
        let base = try XCTUnwrap(FingerGestureClassifier.features(trial()))
        let shifted = try XCTUnwrap(FingerGestureClassifier.features(trial(offset: 0.7)))
        for (a,b) in zip(base, shifted) { XCTAssertEqual(a,b,accuracy:1e-8) }
    }

    func testSuppliedLabelDoesNotInfluencePrediction() throws {
        let up = try XCTUnwrap(FingerGestureClassifier.features(trial(label: .up)))
        let down = try XCTUnwrap(FingerGestureClassifier.features(trial(label: .down)))
        XCTAssertEqual(up, down)
        XCTAssertEqual(FingerGestureClassifier.classify(trial(label: .up)), FingerGestureClassifier.classify(trial(label: .down)))
    }

    func testUntrainedOrientationAndSourceAreRejected() {
        XCTAssertEqual(FingerGestureClassifier.classify(trial(wrist: "right")), .unsure)
        XCTAssertEqual(FingerGestureClassifier.classify(trial(crown: "left")), .unsure)
        XCTAssertEqual(FingerGestureClassifier.classify(trial(acquisition: .deviceMotion)), .unsure)
    }

    func testInvalidFeatureVectorsAreRejected() {
        XCTAssertEqual(FingerGestureClassifier.classify(features: []), .unsure)
        XCTAssertEqual(FingerGestureClassifier.classify(features: [.nan]), .unsure)
        XCTAssertEqual(FingerGestureClassifier.classify(features: Array(repeating: .infinity, count: 42)), .unsure)
    }

    func testInvalidRecordingDoesNotReachPreprocessor() {
        let bad = FingerGestureRecording(version: 2, id: UUID(), label: .still, capturedAt: Date(),
            wrist: "left", crown: "right", device: "Test", systemVersion: "27", requestedInterval: 0.01,
            duration: 3, accelerometer: [], gyroscope: [], acquisition: .rawAccelerometerWithDeviceMotionRotation)
        XCTAssertNil(FingerGestureClassifier.features(bad))
        XCTAssertEqual(FingerGestureClassifier.classify(bad), .unsure)
    }

    func testFrozenModelIsFiniteAndComplete() {
        XCTAssertEqual(FingerGestureModel.templates.count, 17)
        XCTAssertEqual(FingerGestureModel.scales.count, 42)
        XCTAssertTrue(FingerGestureModel.scales.allSatisfy { $0.isFinite && $0 > 0 })
        for template in FingerGestureModel.templates {
            XCTAssertEqual(template.features.count, 42)
            XCTAssertTrue(template.features.allSatisfy(\.isFinite))
        }
    }
}
