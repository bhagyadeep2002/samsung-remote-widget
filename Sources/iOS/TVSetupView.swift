import SwiftUI

struct TVSetupView: View {
    @ObservedObject var relay: PhoneRelayCoordinator
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Watch bridge") {
                    Label(relay.bridgeStatus.title, systemImage: relay.bridgeStatus.symbolName)
                    Text(relay.bridgeStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Watch app", value: relay.watchStatus.title)
                    Text(relay.watchStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("TV") {
                    TextField("TV IP address or hostname", text: $relay.hostInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(!relay.canConfigure)
                    Button("Pair with TV", action: relay.pair)
                        .disabled(!relay.canConfigure)
                    if relay.isPairing {
                        ProgressView()
                        Button("Cancel pairing", action: relay.cancelPairing)
                    }
                    LabeledContent("Pairing", value: relay.hasSavedPairing ? "Saved on this iPhone" : "Not paired")
                    Label(relay.tvReady ? "Connection ready" : "Connection not ready",
                          systemImage: relay.tvReady ? "tv" : "tv.slash")
                    Text(relay.tvStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Forget TV on this iPhone", role: .destructive, action: relay.forget)
                        .disabled(!relay.canConfigure)
                    Text("Keep the TV and iPhone on the same Wi-Fi. Allow Local Network access and approve pairing on the TV. The Watch sends volume taps through this iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Finger gesture recordings") {
                    Text(relay.fingerRecordingStatus)
                    Text("On Watch, record five Up, five Down and five Still trials, then tap Send recordings to iPhone. Wait until all counts arrive here before exporting.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let url = relay.fingerExportURL {
                        ShareLink("Export gesture recordings", item: url)
                    }
                    Text("These are sensor examples, not recognized volume commands.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Samsung TV Remote")
        }
        .onAppear(perform: relay.activate)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                relay.refreshPairing()
                relay.refresh()
            } else if phase == .background {
                relay.phoneBackgrounded()
            }
        }
    }
}
