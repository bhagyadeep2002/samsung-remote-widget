import Foundation

/// Experimental, completed-hold classifier. It has no lifecycle or delivery hooks.
/// All three nearest training templates must agree; otherwise return Unsure.
struct FingerGestureClassifier {
    enum Decision: String, Codable { case up, down, still, unsure }
    static let boundaryTrim: TimeInterval = 0.3

    /// The GO cue must follow the leading samples discarded by preprocessing.
    /// The extra sample interval puts an immediate gesture inside the retained
    /// window even when the two sensor streams have different initial offsets.
    static let cueDelayAfterSettling: TimeInterval = boundaryTrim + 0.01

    static func classify(_ recording: FingerGestureRecording) -> Decision {
        guard recording.isValid, recording.wrist == "left", recording.crown == "right",
              recording.acquisition == .rawAccelerometerWithDeviceMotionRotation,
              let vector = features(recording) else { return .unsure }
        return classify(features: vector)
    }

    static func classify(features vector: [Double]) -> Decision {
        guard vector.count == 42, vector.allSatisfy(\.isFinite) else { return .unsure }
        let templates = FingerGestureModel.templates
        var distances: [(Int, Double)] = []
        for (index, template) in templates.enumerated() {
            var distance = 0.0
            for i in vector.indices {
                let delta = (vector[i] - template.features[i]) / FingerGestureModel.scales[i]
                distance += delta * delta
            }
            distances.append((index, distance))
        }
        distances.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        let nearest = distances.prefix(3).map { templates[$0.0].decision }
        guard nearest.count == 3, let first = nearest.first, nearest.allSatisfy({ $0 == first }) else { return .unsure }
        return first
    }

    /// Same deterministic pipeline as analyze_finger_recordings.py: 100 Hz common
    /// grid, local gravity removal, boundary trim, one-second peak window, 42
    /// statistics. No label, absolute time, duration or static-pose feature.
    static func features(_ recording: FingerGestureRecording) -> [Double]? {
        guard recording.isValid,
              let a0 = recording.accelerometer.first, let a1 = recording.accelerometer.last,
              let g0 = recording.gyroscope.first, let g1 = recording.gyroscope.last else { return nil }
        let start = max(a0.time, g0.time), end = min(a1.time, g1.time)
        var times: [Double] = []
        var i = 0
        while start + Double(i) * 0.01 < end {
            times.append(start + Double(i) * 0.01); i += 1
        }
        guard times.count >= 50 else { return nil }
        var channels = interpolate(recording.accelerometer, at: times) + interpolate(recording.gyroscope, at: times)
        for axis in 0..<3 {
            let baseline = gaussian(channels[axis], sigma: 15)
            channels[axis] = zip(channels[axis], baseline).map(-)
            let offset = quantile(channels[axis+3], fraction: 0.5)
            channels[axis+3] = channels[axis+3].map { $0 - offset }
        }
        let keep = times.indices.filter { times[$0] >= boundaryTrim && times[$0] <= recording.duration - boundaryTrim }
        guard keep.count >= 20 else { return nil }
        channels = channels.map { channel in keep.map { channel[$0] } }
        let energy = gaussian(channels[0].indices.map { index in
            channels[3][index] * channels[3][index] + channels[4][index] * channels[4][index] + channels[5][index] * channels[5][index]
        }, sigma: 3)
        var peak = 0
        for index in energy.indices where energy[index] > energy[peak] { peak = index }
        channels = channels.map { channel in
            (peak-50..<peak+50).map { channel[min(channel.count-1, max(0, $0))] }
        }
        var result: [Double] = []
        for channel in channels {
            let differences = zip(channel.dropFirst(), channel).map(-)
            result += [rms(channel), quantile(channel, fraction: 0.1), quantile(channel, fraction: 0.9),
                       channel.min()!, channel.max()!, rms(differences)]
        }
        for offset in [0, 3] {
            for (a, b) in [(0,1), (0,2), (1,2)] {
                let left = channels[offset+a], right = channels[offset+b]
                let lm = mean(left), rm = mean(right)
                let covariance = mean(zip(left, right).map { ($0 - lm) * ($1 - rm) }) * 100 / 99
                let lv = mean(left.map { ($0-lm) * ($0-lm) }) * 100 / 99
                let rv = mean(right.map { ($0-rm) * ($0-rm) }) * 100 / 99
                result.append(covariance / max(1e-9, sqrt(lv * rv)))
            }
        }
        return result.allSatisfy(\.isFinite) ? result : nil
    }

    private static func interpolate(_ points: [FingerGestureRecording.Point], at times: [Double]) -> [[Double]] {
        var output = Array(repeating: [Double](), count: 3)
        var index = 0
        for time in times {
            while index + 1 < points.count-1 && points[index+1].time < time { index += 1 }
            let left = points[index], right = points[index+1]
            let fraction = min(1, max(0, (time-left.time)/(right.time-left.time)))
            for (axis, (l,r)) in [(left.x,right.x), (left.y,right.y), (left.z,right.z)].enumerated() {
                output[axis].append(l + fraction * (r-l))
            }
        }
        return output
    }

    private static func gaussian(_ values: [Double], sigma: Double) -> [Double] {
        let radius = Int(4 * sigma + 0.5)
        var kernel = (-radius...radius).map { exp(-0.5 * pow(Double($0)/sigma, 2)) }
        let total = kernel.reduce(0,+)
        kernel = kernel.map { $0/total }
        return values.indices.map { i in
            kernel.indices.reduce(0.0) { sum, k in
                sum + kernel[k] * values[min(values.count-1, max(0, i+k-radius))]
            }
        }
    }

    private static func quantile(_ values: [Double], fraction: Double) -> Double {
        let sorted = values.sorted()
        let index = Double(sorted.count-1) * fraction
        let lower = Int(index), upper = min(sorted.count-1, lower+1)
        return sorted[lower] + (sorted[upper]-sorted[lower]) * (index-Double(lower))
    }
    private static func mean(_ values: [Double]) -> Double { values.reduce(0,+)/Double(values.count) }
    private static func rms(_ values: [Double]) -> Double { sqrt(mean(values.map { $0*$0 })) }
}
