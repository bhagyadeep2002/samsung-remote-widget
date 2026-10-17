import SwiftUI

struct FingerCaptureView: View {
    @ObservedObject var capture: FingerCaptureController
    let enabled: Bool
    let connected: Bool
    let begin: () -> Void
    let send: () -> Void
    let clear: () -> Void
    let transferStatus: String
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finger volume").font(.headline)
            Picker("Mode", selection: $capture.mode) {
                ForEach(FingerCaptureController.Mode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .disabled(capture.isRecording)
            if capture.mode == .control {
                Text(connected ? "One volume step per hold. Release stops unsent commands." : "Connect to TV below to use gestures.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if capture.mode == .test {
                Text("Preview only. Release to see the result; TV volume stays unchanged.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if capture.mode != .record {
                Text(capture.testResult).font(.headline)
            } else {
                Picker("Record", selection: $capture.label) {
                    Text("Up").tag(FingerGestureRecording.Label.up)
                    Text("Down").tag(FingerGestureRecording.Label.down)
                    Text("Still").tag(FingerGestureRecording.Label.still)
                }
                .disabled(capture.isRecording)
            }
            HoldCaptureControl(capture: capture, enabled: enabled, begin: begin)
            Text(capture.status).font(.caption2)
            if capture.mode == .control {
                Text("Hold, wait for GO, make one gesture, then rest. Keep holding until the result appears. Release and hold again for another step.")
                    .font(.caption2).foregroundStyle(.secondary)
                if !capture.deliveryStatus.isEmpty { Text(capture.deliveryStatus).font(.caption2) }
            } else {
                Text("Hold, wait for GO, make one gesture, rest, then release after 2–3 seconds. Also test keeping your hand still.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !capture.counts.isEmpty { Text(capture.counts).font(.caption2) }
            if !capture.sensorStatus.isEmpty { Text(capture.sensorStatus).font(.caption2).foregroundStyle(.secondary) }
            if capture.mode == .record {
                Text(capture.savedCounts).font(.caption2)
                Button("Send recordings to iPhone", action: send).disabled(capture.isRecording)
                if !transferStatus.isEmpty { Text(transferStatus).font(.caption2).foregroundStyle(.secondary) }
                Button("Clear Watch recordings", role: .destructive) { confirmsClear = true }
                    .disabled(capture.isRecording)
            }
        }
        .confirmationDialog("Delete Watch copies and cancel pending transfers? Export from iPhone first.", isPresented: $confirmsClear) {
            Button("Delete Watch recordings", role: .destructive, action: clear)
        }
    }
}

private struct HoldCaptureControl: View {
    @ObservedObject var capture: FingerCaptureController
    let enabled: Bool
    let begin: () -> Void
    @GestureState private var touching = false
    @State private var attempted = false
    @State private var cancelled = false

    private var title: String {
        if capture.isRecording {
            if capture.mode == .control {
                return capture.awaitingRelease ? "Release for next gesture" : "Keep holding until result"
            }
            return "Sampling… Release when done"
        }
        switch capture.mode {
        case .control: return "Hold for volume"
        case .test: return "Hold to test"
        case .record: return "Hold to record"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(capture.isRecording ? Color.orange : Color.blue.opacity(enabled ? 1 : 0.3), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        let inside = CGRect(origin: .zero, size: geometry.size).contains(value.location)
                        if !inside {
                            cancelled = true
                            capture.cancel()
                        } else if !attempted && !cancelled && enabled {
                            attempted = true
                            begin()
                        }
                    }
                    .onEnded { value in
                        if !cancelled && CGRect(origin: .zero, size: geometry.size).contains(value.location) {
                            capture.finish()
                        } else { capture.cancel() }
                        attempted = false; cancelled = false
                    })
        }
        .frame(height: 64)
        .accessibilityLabel(title)
        .onChange(of: touching) { _, value in
            if !value {
                // GestureState also resets on system cancellation, which need not
                // call onEnded. Live mode never classifies from either callback.
                capture.cancel()
                attempted = false; cancelled = false
            }
        }
        .onDisappear { capture.cancel() }
    }
}
