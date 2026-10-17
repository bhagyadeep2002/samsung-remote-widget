import Foundation
import XCTest

final class FingerGestureRecordingTests: XCTestCase {
    private func recording(id: UUID = UUID(), label: FingerGestureRecording.Label = .up) -> FingerGestureRecording {
        let points = (0...100).map { FingerGestureRecording.Point(time: Double($0) / 100, x: 0, y: 0, z: -1) }
        return FingerGestureRecording(version: 1, id: id, label: label, capturedAt: Date(), wrist: "left", crown: "right",
            device: "Test Watch", systemVersion: "27", requestedInterval: 0.01, duration: 1,
            accelerometer: points, gyroscope: points)
    }

    func testRoundTripPreservesLabelAndIndependentStreams() throws {
        let trial = recording(label: .down)
        let decoded = try JSONDecoder().decode(FingerGestureRecording.self, from: JSONEncoder().encode(trial))
        XCTAssertTrue(decoded.isValid)
        XCTAssertEqual(decoded.id, trial.id)
        XCTAssertEqual(decoded.label, .down)
        XCTAssertEqual(decoded.accelerometer, trial.accelerometer)
        XCTAssertEqual(FingerGestureRecording.rate(decoded.accelerometer), 100, accuracy: 0.001)
    }

    func testCaptureDoesNotRequireDirectRawGyroscopeAccess() {
        // The rejected Watch configuration has usable device motion even when
        // the direct gyro service is unavailable. It is deliberately not a gate.
        XCTAssertEqual(FingerCaptureAcquisition.select(rawAccelerometer: true, deviceMotion: true),
                       .rawAccelerometerWithDeviceMotionRotation)
        XCTAssertEqual(FingerCaptureAcquisition.select(rawAccelerometer: false, deviceMotion: true), .deviceMotion)
        XCTAssertNil(FingerCaptureAcquisition.select(rawAccelerometer: true, deviceMotion: false))
        XCTAssertNil(FingerCaptureAcquisition.select(rawAccelerometer: false, deviceMotion: false))
    }

    func testVersionTwoSourcesSurviveFileTransferAndExport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FingerRecordingStore(directory: directory)
        let legacy = recording()
        for acquisition in [FingerCaptureAcquisition.rawAccelerometerWithDeviceMotionRotation, .deviceMotion] {
            let trial = FingerGestureRecording(version: 2, id: UUID(), label: legacy.label,
                capturedAt: legacy.capturedAt, wrist: legacy.wrist, crown: legacy.crown,
                device: legacy.device, systemVersion: legacy.systemVersion, requestedInterval: legacy.requestedInterval,
                duration: legacy.duration, accelerometer: legacy.accelerometer, gyroscope: legacy.gyroscope,
                acquisition: acquisition)
            let imported = try store.load(store.save(trial))
            XCTAssertEqual(imported.acquisition, acquisition)
            XCTAssertTrue(imported.isValid)
        }
        try store.save(legacy)
        let export = try JSONDecoder().decode([FingerGestureRecording].self, from: Data(contentsOf: store.export()))
        XCTAssertEqual(export.count, 3)
        XCTAssertTrue(export.allSatisfy(\.isValid))
        XCTAssertNil(export.first { $0.version == 1 }?.acquisition)
    }

    func testVersionTwoWithoutSourceAndMislabelledLegacyAreRejected() throws {
        let trial = recording()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(trial)) as? [String: Any])
        object["version"] = 2
        var decoded = try JSONDecoder().decode(FingerGestureRecording.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isValid)
        object["version"] = 1
        object["acquisition"] = FingerCaptureAcquisition.deviceMotion.rawValue
        decoded = try JSONDecoder().decode(FingerGestureRecording.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isValid)
    }

    func testSettlingStaleFutureAndOutOfOrderSamplesAreIgnored() {
        var buffer = FingerCaptureBuffer()
        let id = UUID()
        buffer.begin(generation: id, now: 10)
        func append(_ timestamp: Double, now: Double) {
            buffer.append(acceleration: true, timestamp: timestamp, x: 1, y: 2, z: 3, generation: id, now: now)
        }
        append(10.1, now: 10.1) // settling
        append(10.4, now: 10.7) // stale
        append(10.7, now: 10.6) // future
        append(10.5, now: 10.5)
        append(10.5, now: 10.5) // duplicate
        append(10.45, now: 10.5) // out of order
        append(.nan, now: 10.5)
        XCTAssertEqual(buffer.accelerometer.count, 1)
        XCTAssertEqual(buffer.accelerometer.first!.time, 0.15, accuracy: 0.0001)
        XCTAssertTrue(buffer.gyroscope.isEmpty)
    }

    func testCancellationAndNewHoldRejectOldCallbacks() {
        var buffer = FingerCaptureBuffer()
        let old = UUID(), next = UUID()
        buffer.begin(generation: old, now: 0)
        buffer.cancel()
        buffer.append(acceleration: true, timestamp: 1, x: 1, y: 1, z: 1, generation: old, now: 1)
        XCTAssertTrue(buffer.accelerometer.isEmpty)
        XCTAssertNil(buffer.finish(generation: old, now: 2))
        buffer.begin(generation: next, now: 3)
        buffer.append(acceleration: true, timestamp: 4, x: 1, y: 1, z: 1, generation: old, now: 4)
        XCTAssertTrue(buffer.accelerometer.isEmpty)
        XCTAssertNil(buffer.finish(generation: old, now: 5))
        XCTAssertEqual(buffer.generation, next)
    }

    func testReleaseTrimsTouchEndAndDiscardsBuffer() throws {
        var buffer = FingerCaptureBuffer()
        let id = UUID()
        buffer.begin(generation: id, now: 0)
        for i in 0...100 {
            let timestamp = buffer.sampleStart + Double(i) / 100
            buffer.append(acceleration: true, timestamp: timestamp, x: 0, y: 0, z: 0, generation: id, now: timestamp)
        }
        let (duration, points, _) = try XCTUnwrap(buffer.finish(generation: id, now: 1.35))
        XCTAssertEqual(duration, 0.9, accuracy: 0.0001)
        XCTAssertTrue(points.allSatisfy { $0.time <= duration })
        XCTAssertLessThan(points.count, 101)
        XCTAssertNil(buffer.generation)
        XCTAssertTrue(buffer.accelerometer.isEmpty)
        XCTAssertNil(buffer.finish(generation: id, now: 2))
    }

    func testShortHoldDiscardedAndAllStreamsBounded() throws {
        var buffer = FingerCaptureBuffer()
        let id = UUID()
        buffer.begin(generation: id, now: 0)
        XCTAssertNil(buffer.finish(generation: id, now: 0.5))
        XCTAssertNil(buffer.generation)
        buffer.begin(generation: id, now: 0)
        for i in 0...6000 {
            let time = buffer.sampleStart + Double(i) / 1000
            for acceleration in [true, false] {
                buffer.append(acceleration: acceleration, timestamp: time, x: 0, y: 0, z: 0, generation: id, now: time)
            }
        }
        XCTAssertLessThanOrEqual(buffer.accelerometer.count, 1000)
        XCTAssertLessThanOrEqual(buffer.gyroscope.count, 1000)
        let (duration, _, _) = try XCTUnwrap(buffer.finish(generation: id, now: 99))
        XCTAssertEqual(duration, 4)
    }

    func testNonFiniteAndMissingStreamCannotBeSaved() throws {
        let trial = recording()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(trial)) as? [String: Any])
        object["gyroscope"] = []
        let missing = try JSONDecoder().decode(FingerGestureRecording.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(missing.isValid)
        object["gyroscope"] = object["accelerometer"]
        object["version"] = 99
        let future = try JSONDecoder().decode(FingerGestureRecording.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(future.isValid)
        var buffer = FingerCaptureBuffer()
        let id = UUID()
        buffer.begin(generation: id, now: 0)
        buffer.append(acceleration: true, timestamp: 1, x: .infinity, y: 0, z: 0, generation: id, now: 1)
        XCTAssertTrue(buffer.accelerometer.isEmpty)
    }

    func testStoreImportIdempotentAndExportExcludesBatchFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FingerRecordingStore(directory: directory)
        let trial = recording(label: .still)
        let url = try store.save(trial)
        XCTAssertTrue(try store.load(url).isValid)
        try store.save(trial)
        XCTAssertEqual(store.recordings.count, 1)
        let batch = try store.export()
        XCTAssertEqual(store.recordings.count, 1)
        let trials = try JSONDecoder().decode([FingerGestureRecording].self, from: Data(contentsOf: batch))
        XCTAssertEqual(trials.map(\.label), [.still])
        try store.removeAll()
        XCTAssertTrue(store.recordings.isEmpty)
    }

    func testStoreRejectsOversizedFileAndStorageOverflow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FingerRecordingStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oversized = directory.appendingPathComponent("oversized.json")
        try Data(repeating: 0, count: FingerRecordingStore.maximumBytes + 1).write(to: oversized)
        XCTAssertThrowsError(try store.load(oversized))
        let first = recording()
        try store.save(first)
        for _ in 1..<FingerRecordingStore.maximumRecordings { try store.save(recording()) }
        XCTAssertThrowsError(try store.save(recording()))
        XCTAssertNoThrow(try store.save(first)) // duplicate transfer at capacity
    }
}
