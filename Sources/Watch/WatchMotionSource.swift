import CoreMotion
import Foundation

/// Main-queue acquisition avoids creating a Task/backlog for every sensor sample.
/// Late callbacks are rejected by activation generation, and the processor also
/// checks timestamp freshness. No transport or gesture logic lives in this class.
@MainActor
final class WatchMotionSource {
    private let manager = CMMotionManager()
    private var generation: UUID?

    var available: Bool { manager.isDeviceMotionAvailable }

    func start(generation: UUID, interval: TimeInterval,
               onSample: @escaping @MainActor (MotionSample) -> Void,
               onError: @escaping @MainActor (String) -> Void) -> String? {
        stop()
        guard available else { onError("Motion is unavailable. Use the volume buttons."); return nil }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame
        let name: String
        if frames.contains(.xArbitraryZVertical) {
            frame = .xArbitraryZVertical; name = "Arbitrary vertical"
        } else if frames.contains(.xArbitraryCorrectedZVertical) {
            frame = .xArbitraryCorrectedZVertical; name = "Corrected arbitrary vertical"
        } else {
            onError("A relative motion reference is unavailable. Use the volume buttons.")
            return nil
        }
        self.generation = generation
        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, error in
            // Core Motion is explicitly delivering on OperationQueue.main.
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                guard error == nil, let motion else {
                    self.stop()
                    onError("Motion stopped. Check motion permission and try again.")
                    return
                }
                let q = motion.attitude.quaternion
                // Adapt reference-to-device attitude into the processor's
                // device-to-reference convention. Physical preview validates this
                // convention, selected case axis and sign before any TV delivery.
                let attitude = MotionQuaternion(x: q.x, y: q.y, z: q.z, w: q.w).conjugate
                onSample(MotionSample(timestamp: motion.timestamp, attitude: attitude,
                    rotationRate: .init(x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z),
                    gravity: .init(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
                    userAcceleration: .init(x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z)))
            }
        }
        return name
    }

    func stop() {
        generation = nil
        manager.stopDeviceMotionUpdates()
    }
}
