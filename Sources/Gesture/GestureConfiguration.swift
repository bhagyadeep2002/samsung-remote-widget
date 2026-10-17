import Foundation

struct GestureConfiguration: Sendable {
    enum Axis: String, CaseIterable, Identifiable, Sendable {
        case x, y
        var id: String { rawValue }
        var vector: MotionVector {
            self == .x ? MotionVector(x: 1, y: 0, z: 0) : MotionVector(x: 0, y: 1, z: 0)
        }
    }
    enum Wrist: Sendable { case left, right }
    enum Crown: Sendable { case left, right }
    var axis: Axis = .x // across the case toward the crown; anatomical alignment is a hypothesis
    var wrist: Wrist = .left
    var crown: Crown = .right
    var inverted = false
    var sampleInterval: TimeInterval = 0.02
    var calibrationDuration: TimeInterval = 0.4
    var calibrationTimeout: TimeInterval = 2
    var calibrationSpeedDegrees = 8.0
    var calibrationAcceleration = 0.15
    var calibrationSpreadDegrees = 3.0
    var deadZoneDegrees = 5.0
    var detentDegrees = 12.0
    var reversalDegrees = 3.0
    var filterTimeConstant: TimeInterval = 0.04
    var commandInterval: TimeInterval = 0.25
    var maximumSampleGap: TimeInterval = 0.15
    var maximumSampleAge: TimeInterval = 0.15
    var maximumTwistDegrees = 70.0
    var maximumSwingDegrees = 35.0
    var maximumSpeedDegrees = 720.0
    var maximumHold: TimeInterval = 10

    // Proposed mapping only. A silent physical preview must establish direction.
    var twistAxis: MotionVector {
        let sign = (wrist == .left ? 1.0 : -1.0) * (crown == .right ? 1.0 : -1.0)
        return axis.vector.scaled(sign)
    }
}
