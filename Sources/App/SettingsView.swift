import SwiftUI
import WidgetKit

struct SettingsView: View {
    @AppStorage("tvHost", store: SharedPreferences.defaults)
    private var host = ""

    @AppStorage("connectionStatus", store: SharedPreferences.defaults)
    private var status = "Enter the TV's local IP address and pair."

    @State private var isPairing = false
    @State private var showingForgetConfirmation = false

    var body: some View {
        Form {
            Section("Samsung TV") {
                TextField("TV IP address or network name", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Text("Connect the Mac and TV to the same home network.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Pairing") {
                HStack(alignment: .firstTextBaseline) {
                    Button {
                        pairWithTV()
                    } label: {
                        if isPairing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 116)
                        } else {
                            Text("Pair with TV")
                                .frame(width: 116)
                        }
                    }
                    .disabled(
                        isPairing || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Forget this TV…", role: .destructive) {
                    showingForgetConfirmation = true
                }
                .confirmationDialog(
                    "Remove the saved pairing for this address?",
                    isPresented: $showingForgetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Forget TV", role: .destructive) {
                        forgetTV()
                    }
                }
            }

            Text("Approve Samsung TV Remote on the TV. Pairing credentials are saved in this Mac's Keychain.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: host) {
            SharedPreferences.saveHost(host.trimmingCharacters(in: .whitespacesAndNewlines))
            SharedPreferences.saveStatus("TV address saved. Pair with your TV.")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func pairWithTV() {
        isPairing = true
        SharedPreferences.saveStatus("Approve the connection request on your TV.")

        Task {
            defer {
                isPairing = false
                WidgetCenter.shared.reloadAllTimelines()
            }
            do {
                try await SamsungTVClient.pair(with: host)
            } catch {
                SharedPreferences.saveStatus(error.localizedDescription)
            }
        }
    }

    private func forgetTV() {
        let savedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try PairingCredentialStore.removeCredentials(for: savedHost)
            SharedPreferences.saveStatus("Pairing removed.")
        } catch {
            SharedPreferences.saveStatus(error.localizedDescription)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
