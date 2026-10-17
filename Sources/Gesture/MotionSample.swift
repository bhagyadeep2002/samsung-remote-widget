import Foundation

struct MotionVector: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
    static let zero = Self(x: 0, y: 0, z: 0)
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    var length: Double { sqrt(dot(self)) }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z }
    func scaled(_ value: Double) -> Self { Self(x: x * value, y: y * value, z: z * value) }
}

/// Hamilton quaternion (x, y, z, w), rotating device coordinates into reference
/// coordinates. Relative rotation is inverse(neutral) * current, in neutral axes.
struct MotionQuaternion: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
    var w: Double
    static let identity = Self(x: 0, y: 0, z: 0, w: 1)
    var conjugate: Self { Self(x: -x, y: -y, z: -z, w: w) }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z + w * other.w }
    func scaled(_ value: Double) -> Self { Self(x: x * value, y: y * value, z: z * value, w: w * value) }
    func adding(_ q: Self) -> Self { Self(x: x + q.x, y: y + q.y, z: z + q.z, w: w + q.w) }
    var normalized: Self? {
        let norm = sqrt(dot(self))
        guard isFinite, norm.isFinite, norm > 0.000001 else { return nil }
        return scaled(1 / norm)
    }
    static func * (a: Self, b: Self) -> Self {
        Self(x: a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
             y: a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
             z: a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w,
             w: a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z)
    }
    static func rotation(axis: MotionVector, radians: Double) -> Self {
        let vector = axis.scaled(sin(radians / 2) / axis.length)
        return Self(x: vector.x, y: vector.y, z: vector.z, w: cos(radians / 2))
    }
}

struct MotionSample: Sendable {
    let timestamp: TimeInterval // seconds since Watch boot
    let attitude: MotionQuaternion
    let rotationRate: MotionVector // radians / second, device axes
    let gravity: MotionVector // g, device axes
    let userAcceleration: MotionVector // g, device axes
}

struct TwistIntent: Equatable, Sendable {
    enum Direction: String, Sendable { case up, down }
    let direction: Direction
    let generation: UUID
    let timestamp: TimeInterval
}
