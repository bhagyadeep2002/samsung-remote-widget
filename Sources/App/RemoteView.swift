import AppKit
import SwiftUI

struct RemoteView: View {
    @AppStorage("tvHost", store: SharedPreferences.defaults) private var host = ""
    @AppStorage("connectionStatus", store: SharedPreferences.defaults)
    private var status = "Enter your TV address below to get started."

    @State private var isPaired = false
    @State private var pendingCommands = 0
    @State private var isPairing = false
    @State private var showsSetup = false
    @State private var showsForgetConfirmation = false
    @State private var hasError = false
    @State private var showsNumberPad = false

    private static let digits: [SamsungRemoteKey] = [
        .digit1, .digit2, .digit3,
        .digit4, .digit5, .digit6,
        .digit7, .digit8, .digit9
    ]

    private var isBusy: Bool { isPairing || pendingCommands > 0 }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "tv")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Samsung TV").font(.headline)
                    Text(isPaired ? host : "Set up your remote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(isPaired ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(isPaired ? "Paired" : "Not paired")
            }

            VStack(spacing: 12) {
                HStack {
                    remoteButton(.back, symbol: "arrow.uturn.backward")
                    remoteButton(.home, symbol: "house")
                    Button {
                        showsNumberPad.toggle()
                        perform(showsNumberPad ? .showNumberPad : .hideNumberPad,
                                label: showsNumberPad ? "Open number pad" : "Close number pad")
                    } label: {
                        Group {
                            if showsNumberPad {
                                Image(systemName: "dpad")
                            } else {
                                Text("123")
                            }
                        }
                        .font(.headline)
                        .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel(showsNumberPad ? "Show navigation controls" : "Show number pad")
                    .help(showsNumberPad ? "Close the TV’s number pad and switch back to arrows" : "Open the TV’s number pad and enter numbers from this app")
                    Spacer()
                    remoteButton(.powerOff, symbol: "power")
                        .tint(.red)
                }

                if showsNumberPad {
                    numberPad
                } else {
                    navigationPad
                }

                HStack(spacing: 8) {
                    remoteButton(.volumeDown, symbol: "speaker.minus")
                    remoteButton(.mute, symbol: "speaker.slash")
                    remoteButton(.volumeUp, symbol: "speaker.plus")
                    Divider().frame(height: 24)
                    remoteButton(.play, symbol: "play.fill")
                    remoteButton(.pause, symbol: "pause.fill")
                }
            }
            .disabled(!isPaired || isPairing)

            HStack(alignment: .top, spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: hasError ? "exclamationmark.circle" : "info.circle")
                        .foregroundStyle(hasError ? Color.orange : Color.secondary)
                }
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Divider()

            DisclosureGroup("TV setup", isExpanded: $showsSetup) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("TV IP address or network name", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .disabled(isBusy)
                        .onSubmit { if !isBusy && !host.isEmpty { pairWithTV() } }

                    Text("Keep your TV on and connected to the same home network as this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(isPairing ? "Waiting for TV…" : "Pair with TV") {
                            pairWithTV()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()

                        Button("Forget TV…", role: .destructive) {
                            showsForgetConfirmation = true
                        }
                        .disabled(isBusy || !isPaired)
                    }
                }
                .padding(.top, 10)
            }
            .confirmationDialog("Remove the saved pairing for this TV?", isPresented: $showsForgetConfirmation) {
                Button("Forget TV", role: .destructive) { forgetTV() }
                Button("Cancel", role: .cancel) { }
            }

            HStack {
                Text("Power turns the TV off only.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            refreshPairing()
            showsSetup = !isPaired
            if !hasError && !isBusy {
                SharedPreferences.saveStatus(isPaired ? "Your remote is ready." : "Enter your TV address below and pair with your TV.")
            }
        }
        .task {
            if isPaired {
                try? await SamsungTVClient.prepare()
                if showsNumberPad { try? await SamsungTVClient.perform(.showNumberPad) }
            }
        }
        .onDisappear {
            Task { try? await SamsungTVClient.perform(.hideNumberPad) }
        }
        .onChange(of: host) {
            refreshPairing()
            if !hasError {
                SharedPreferences.saveStatus(isPaired ? "Saved pairing available." : "TV address saved. Pair with your TV.")
            }
            let shouldPrepare = isPaired
            Task {
                await SamsungTVClient.disconnect()
                if shouldPrepare { try? await SamsungTVClient.prepare() }
            }
        }
    }

    private var navigationPad: some View {
        VStack(spacing: 6) {
            remoteButton(.up, symbol: "chevron.up")
            HStack(spacing: 6) {
                remoteButton(.left, symbol: "chevron.left")
                remoteButton(.select, symbol: "circle", title: "OK")
                remoteButton(.right, symbol: "chevron.right")
            }
            remoteButton(.down, symbol: "chevron.down")
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
    }

    private var numberPad: some View {
        VStack(spacing: 10) {
            HStack {
                Text("TV number entry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restart") {
                    perform(.restartNumberPad, label: "Restart number entry")
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(isBusy)
                .help("Close and reopen the TV’s keypad with 6 selected. Use this if the TV selection changed outside this app.")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Self.digits, id: \.rawValue) { key in
                    remoteButton(key, symbol: "number", title: key.spokenName)
                }
                Button {
                    perform(.deleteNumber, label: "Delete number")
                } label: {
                    Image(systemName: "delete.left").frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Delete last number on TV")
                remoteButton(.digit0, symbol: "number", title: "0")
                Button {
                    perform(.finishNumberEntry, label: "Done entering numbers")
                } label: {
                    Text("Done").font(.caption.weight(.semibold)).frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Confirm number entry on TV")
            }
        }
        .frame(width: 200)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
    }

    private func remoteButton(_ key: SamsungRemoteKey, symbol: String, title: String? = nil) -> some View {
        Button {
            send(key)
        } label: {
            Group {
                if let title {
                    Text(title).font(.headline)
                } else {
                    Image(systemName: symbol).font(.body.weight(.medium))
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(key.spokenName)
        .help(key.spokenName)
    }

    private func refreshPairing() {
        let savedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let token = try PairingCredentialStore.token(for: savedHost)
            let pin = try PairingCredentialStore.certificatePin(for: savedHost)
            isPaired = !savedHost.isEmpty && token != nil && pin != nil
            hasError = false
        } catch {
            isPaired = false
            hasError = true
            SharedPreferences.saveStatus(error.localizedDescription)
        }
    }

    private func pairWithTV() {
        guard !isBusy else { return }
        isPairing = true
        hasError = false
        SharedPreferences.saveStatus("Approve the connection request on your TV.")

        Task { @MainActor in
            defer { isPairing = false }
            do {
                try await SamsungTVClient.pair(with: host)
                refreshPairing()
                if isPaired { showsSetup = false }
            } catch {
                hasError = true
                SharedPreferences.saveStatus(error.localizedDescription)
            }
        }
    }

    private func send(_ key: SamsungRemoteKey) {
        perform(.key(key), label: key.spokenName)
    }

    private func perform(_ action: TVRemoteAction, label: String) {
        guard !isPairing, isPaired else { return }
        pendingCommands += 1
        hasError = false
        SharedPreferences.saveStatus("Sending \(label)…")

        Task { @MainActor in
            defer { pendingCommands -= 1 }
            do {
                try await SamsungTVClient.perform(action)
                hasError = false
                SharedPreferences.saveStatus("Sent \(label).")
            } catch {
                hasError = true
                SharedPreferences.saveStatus(error.localizedDescription)
            }
        }
    }

    private func forgetTV() {
        do {
            try PairingCredentialStore.removeCredentials(for: host.trimmingCharacters(in: .whitespacesAndNewlines))
            Task { await SamsungTVClient.disconnect() }
            isPaired = false
            hasError = false
            SharedPreferences.saveStatus("Pairing removed. Pair again to use the remote.")
        } catch {
            hasError = true
            SharedPreferences.saveStatus(error.localizedDescription)
        }
    }
}
