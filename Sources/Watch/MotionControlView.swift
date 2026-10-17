import SwiftUI

struct MotionControlView: View {
    @ObservedObject var motion: WatchMotionController
    let connected: Bool
    let paused: Bool
    let pause: () -> Void
    let resume: () -> Void
    @State private var showsSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(motion.isRunning ? "Wrist volume on" : "Wrist volume off",
                  systemImage: motion.isRunning ? "hand.raised.fill" : "pause.circle")
                .font(.headline)
                .foregroundStyle(motion.isRunning ? Color.green : Color.secondary)
            Text(motion.status).font(.caption2)
            Text(motion.preview).font(.headline)
            Text(motion.deliveryStatus).font(.caption2).foregroundStyle(.secondary)
            if motion.isRunning {
                Button("Pause motion", action: pause)
            } else {
                Button(paused ? "Resume motion" : "Recalibrate", action: resume)
                    .disabled(!connected)
            }
            Text("Clockwise + · Anticlockwise −")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(showsSetup ? "Hide motion setup" : "Motion setup") { showsSetup.toggle() }
            if showsSetup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pause before changing setup.").font(.caption2)
                    Toggle("Reverse direction", isOn: $motion.inverted)
                    Picker("Twist axis", selection: $motion.axis) {
                        Text("Across case (X)").tag(GestureConfiguration.Axis.x)
                        Text("Along strap (Y)").tag(GestureConfiguration.Axis.y)
                    }
                    Text(motion.orientation).font(.caption2)
                    Text(motion.sensorStatus).font(.caption2)
                    Text("Twist: \(Int(motion.angleDegrees))°").font(.caption2)
                }
                .disabled(motion.isRunning)
            }
        }
    }
}
