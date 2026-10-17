import SwiftUI

struct VolumeRemoteView: View {
    @ObservedObject var model: WatchRemoteModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Samsung TV")
                    .font(.headline)

                FingerCaptureView(capture: model.fingerCapture, enabled: model.canRecordFingerGesture,
                                  connected: model.isConnected,
                                  begin: model.beginFingerCapture, send: model.sendFingerRecordings,
                                  clear: model.clearFingerRecordings,
                                  transferStatus: model.recordingTransferStatus)
                Text(model.tvStatus)
                    .font(.caption2)
                HStack {
                    Button { model.volume(up: false) } label: {
                        Image(systemName: "speaker.minus.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityLabel("Volume down")
                    Button { model.volume(up: true) } label: {
                        Image(systemName: "speaker.plus.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityLabel("Volume up")
                }
                .disabled(!model.canSend || model.sending)
                if model.isConnected {
                    Button("Disconnect") { model.stop() }
                } else {
                    Button(model.connecting ? "Connecting…" : "Connect to TV", action: model.connect)
                        .disabled(model.connecting)
                }
                if let timing = model.latencyStatus {
                    Text(timing)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("TV response time is not measured.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Label(model.bridgeStatus.title, systemImage: model.bridgeStatus.symbolName)
                    .font(.caption2)
                Text(model.phoneStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .onAppear { model.setForeground(true) }
        .onDisappear { model.setForeground(false) }
        .onChange(of: scenePhase) { _, phase in
            model.setForeground(phase == .active)
        }
    }
}
