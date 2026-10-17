import Combine
import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class PhoneRelayCoordinator: NSObject, ObservableObject {
    enum BridgeStatus: Equatable {
        case unsupported
        case starting
        case active
        case switchingWatch
        case failed(String)

        var title: String {
            switch self {
            case .unsupported: "Watch Connectivity unavailable"
            case .starting: "Starting"
            case .active: "Active"
            case .switchingWatch: "Switching Watch"
            case let .failed(message): "Activation failed: \(message)"
            }
        }

        var detail: String {
            switch self {
            case .unsupported:
                "This device cannot run the Watch relay."
            case .starting:
                "Waiting for Watch Connectivity to activate."
            case .active:
                "Watch Connectivity is active. TV readiness is reported separately below."
            case .switchingWatch:
                "The paired Watch is changing. The session will activate again when switching finishes."
            case .failed:
                "The Watch bridge did not activate. Reopen this app to retry."
            }
        }

        var symbolName: String {
            switch self {
            case .unsupported, .failed: "xmark.circle"
            case .starting, .switchingWatch: "arrow.triangle.2.circlepath"
            case .active: "checkmark.circle"
            }
        }
    }

    enum WatchStatus: Equatable {
        case checking
        case noWatchPaired
        case appNotInstalled
        case reachable
        case notReachable

        var title: String {
            switch self {
            case .checking: "Checking"
            case .noWatchPaired: "No Watch paired"
            case .appNotInstalled: "Watch app not installed"
            case .reachable: "Reachable"
            case .notReachable: "Not reachable"
            }
        }

        var detail: String {
            switch self {
            case .checking: "Checking this iPhone's paired Watch and app state."
            case .noWatchPaired: "Pair an Apple Watch with this iPhone to continue."
            case .appNotInstalled: "Install Samsung TV Remote on the paired Watch."
            case .reachable: "The Watch app can exchange live messages with this iPhone."
            case .notReachable: "Open the Watch app to make the live bridge reachable."
            }
        }
    }

    @Published private(set) var bridgeStatus: BridgeStatus = .starting
    @Published private(set) var watchStatus: WatchStatus = .checking
    @Published private(set) var fingerRecordingStatus = "No finger recordings received yet."
    @Published private(set) var fingerExportURL: URL?

    @Published var hostInput = SharedPreferences.host
    @Published private(set) var tvStatus = "Set up your TV on this iPhone."
    @Published private(set) var isPairing = false
    @Published private(set) var tvReady = false
    @Published private(set) var hasSavedPairing = false
    private var pairingTask: Task<Void, Never>?
    private var leaseMonitor: Task<Void, Never>?
    @Published private(set) var preparing = false
    @Published private(set) var sending = false
    private var revision = UUID()
    private var lastTVUse: TimeInterval = 0
    private var session: WCSession?
    private var didActivate = false

    override init() {
        super.init()
        refreshFingerRecordings()
        activate()
    }

    private func refreshFingerRecordings() {
        let store = FingerRecordingStore()
        let trials = store.recordings.compactMap { try? store.load($0) }
        guard !trials.isEmpty else { return }
        do {
            fingerExportURL = try store.export()
            fingerRecordingStatus = FingerGestureRecording.Label.allCases.map { label in
                "\(label.rawValue.capitalized): \(trials.filter { $0.label == label }.count)"
            }.joined(separator: " · ")
        } catch {
            fingerExportURL = nil
            fingerRecordingStatus = "Could not export recordings: \(error.localizedDescription)"
        }
    }

    func activate() {
        guard !didActivate else {
            refresh()
            return
        }
        didActivate = true

        guard WCSession.isSupported() else {
            bridgeStatus = .unsupported
            watchStatus = .noWatchPaired
            return
        }

        let session = WCSession.default
        session.delegate = self
        self.session = session
        bridgeStatus = .starting
        session.activate()
        startLeaseMonitor()
        refreshPairing()
        refresh()
    }

    func refresh() {
        guard let session else { return }

        switch session.activationState {
        case .notActivated:
            bridgeStatus = .starting
            watchStatus = .checking
        case .inactive:
            bridgeStatus = .switchingWatch
            watchStatus = .checking
        case .activated:
            bridgeStatus = .active
            refreshWatchStatus(using: session)
        @unknown default:
            bridgeStatus = .starting
            watchStatus = .checking
        }
    }

    private func refreshWatchStatus(using session: WCSession) {
        guard session.isPaired else {
            invalidateTVSession()
            watchStatus = .noWatchPaired
            return
        }
        guard session.isWatchAppInstalled else {
            invalidateTVSession()
            watchStatus = .appNotInstalled
            return
        }
        watchStatus = session.isReachable ? .reachable : .notReachable
        if !session.isReachable && !isPairing { invalidateTVSession() }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var canConfigure: Bool { !isPairing && !preparing && !sending }

    func pair() {
        guard canConfigure else { return }
        invalidateTVSession()
        let currentRevision = revision
        let host = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        SharedPreferences.saveHost(host)
        isPairing = true
        tvStatus = "Approve the connection request on your TV."
        pairingTask = Task {
            defer { isPairing = false; pairingTask = nil }
            do {
                try await SamsungTVClient.pair(with: host)
                guard currentRevision == revision, !Task.isCancelled else {
                    await SamsungTVClient.disconnect()
                    return
                }
                hasSavedPairing = true
                tvReady = true
                lastTVUse = now
                tvStatus = "Paired. Open the Watch remote to connect."
            } catch {
                guard currentRevision == revision else { return }
                tvReady = false
                tvStatus = Self.safeError(error)
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        invalidateTVSession()
        Task { await SamsungTVClient.disconnect() }
        tvStatus = "Pairing cancelled."
    }

    func forget() {
        guard canConfigure else { return }
        invalidateTVSession()
        let currentRevision = revision
        let host = SharedPreferences.host
        isPairing = true
        pairingTask = Task {
            defer { isPairing = false; pairingTask = nil }
            await SamsungTVClient.disconnect()
            guard currentRevision == revision, !Task.isCancelled else { return }
            do {
                try PairingCredentialStore.removeCredentials(for: host)
                hasSavedPairing = false
                tvStatus = "Pairing removed from this iPhone."
            } catch { tvStatus = Self.safeError(error) }
        }
    }

    func refreshPairing() {
        do {
            hasSavedPairing = try PairingCredentialStore.token(for: SharedPreferences.host) != nil &&
                PairingCredentialStore.certificatePin(for: SharedPreferences.host) != nil
            if hasSavedPairing && !tvReady && !isPairing {
                tvStatus = "Saved pairing. Connect to the TV from your Watch."
            }
        } catch { tvStatus = Self.safeError(error) }
    }

    func phoneBackgrounded() {
        if isPairing { cancelPairing() }
        // WCSession may wake the phone for live Watch requests. No extended runtime
        // or background mode is requested; hardware testing must establish viability.
    }

    private func invalidateTVSession() {
        revision = UUID()
        SamsungTVClient.volumeGate.cancel()
        tvReady = false
    }

    private func startLeaseMonitor() {
        guard leaseMonitor == nil else { return }
        leaseMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                if !self.isPairing && !self.preparing && self.lastTVUse > 0 &&
                    !SamsungTVClient.volumeGate.hasLease(now: self.now) && self.now - self.lastTVUse > 2 {
                    self.invalidateTVSession()
                    self.lastTVUse = 0
                    await SamsungTVClient.disconnect()
                }
            }
        }
    }

    private static func safeError(_ error: Error) -> String {
        if let error = error as? SamsungTVError { return error.localizedDescription }
        if let error = error as? CredentialStoreError { return error.localizedDescription }
        if error is CancellationError { return "Cancelled or expired. Try a fresh connection." }
        return "Cannot connect to the TV. Check Local Network permission, Wi-Fi and TV power."
    }

    private func handle(_ message: VolumeBridgeMessage) async -> VolumeBridgeMessage {
        guard message.version == 1, session?.activationState == .activated,
              session?.isReachable == true, !isPairing else { return message.reply("notReady") }
        switch message.kind {
        case "prepare":
            guard !preparing, !sending else { return message.reply("notReady") }
            preparing = true
            invalidateTVSession()
            let currentRevision = revision
            defer { preparing = false }
            do {
                tvStatus = "Connecting to TV…"
                try await SamsungTVClient.prepare()
                guard revision == currentRevision, session?.isReachable == true else {
                    await SamsungTVClient.disconnect()
                    return message.reply("cancelled")
                }
                let id = SamsungTVClient.volumeGate.begin(now: now)
                var reply = message.reply("ready")
                reply.sessionID = id
                reply.permitID = SamsungTVClient.volumeGate.issue(session: id, now: now)
                lastTVUse = now
                tvReady = true
                tvStatus = "TV connection ready for Watch volume."
                return reply
            } catch {
                tvReady = false
                tvStatus = Self.safeError(error)
                await SamsungTVClient.disconnect()
                return message.reply("notReady", detail: tvStatus)
            }
        case "heartbeat":
            guard let id = message.sessionID else { return message.reply("rejected") }
            guard await SamsungTVClient.isReady() else {
                tvReady = false
                return message.reply("notReady", detail: "TV connection lost. Connect again.")
            }
            guard let permit = SamsungTVClient.volumeGate.issue(session: id, now: now,
                    activation: message.activationID, activationSequence: message.activationSequence) else {
                return message.reply("notReady", detail: "Watch control session expired. Connect again.")
            }
            lastTVUse = now
            var reply = message.reply("ready")
            reply.permitID = permit
            return reply
        case "motionBegin":
            guard !sending, let id = message.sessionID, let activation = message.activationID,
                  let sequence = message.activationSequence, await SamsungTVClient.isReady(), !sending,
                  SamsungTVClient.volumeGate.beginMotion(session: id, activation: activation, sequence: sequence, now: now),
                  let permit = SamsungTVClient.volumeGate.issue(session: id, now: now,
                      activation: activation, activationSequence: sequence) else { return message.reply("notReady") }
            var reply = message.reply("ready")
            reply.permitID = permit
            return reply
        case "motionEnd":
            guard let id = message.sessionID, let activation = message.activationID,
                  let sequence = message.activationSequence else { return message.reply("rejected") }
            SamsungTVClient.volumeGate.endMotion(session: id, activation: activation, sequence: sequence)
            return message.reply("cancelled")
        case "end":
            if let id = message.sessionID { SamsungTVClient.volumeGate.cancel(session: id) }
            return message.reply("cancelled")
        case "step", "motionStep":
            let received = now
            guard let id = message.sessionID,
                  let deadline = SamsungTVClient.volumeGate.consume(message, now: now), !sending else {
                return message.reply("expired")
            }
            sending = true
            defer { sending = false }
            do {
                try await SamsungTVClient.sendVolume(up: message.direction == "up", session: id, deadline: deadline,
                    activation: message.activationID, activationSequence: message.activationSequence)
                tvStatus = "Volume command sent; TV response unconfirmed."
                var reply = message.reply("sentToSocket")
                reply.relayMilliseconds = max(0, (now - received) * 1000)
                return reply
            } catch is CancellationError {
                tvStatus = "Volume tap expired before transmission."
                return message.reply("cancelled")
            } catch {
                invalidateTVSession()
                tvStatus = "Send outcome unknown. Reconnect before trying a new tap."
                return message.reply("unknown")
            }
        default: return message.reply("rejected")
        }
    }

    private func completeActivation(stateValue: Int, errorMessage: String?) {
        let state = WCSessionActivationState(rawValue: stateValue) ?? .notActivated
        if let errorMessage, state != .activated {
            bridgeStatus = .failed(errorMessage)
            watchStatus = .checking
            return
        }
        refresh()
    }
}

extension PhoneRelayCoordinator: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kind"] as? String == FingerRecordingStore.transferKind else { return }
        // WCSession's temporary URL expires when this delegate call returns.
        // Validate and persist synchronously before scheduling main-actor UI work.
        let failure: String?
        do {
            let store = FingerRecordingStore()
            try store.save(store.load(file.fileURL))
            failure = nil
        } catch { failure = error.localizedDescription }
        Task { @MainActor [weak self] in
            if let failure { self?.fingerRecordingStatus = "Recording import failed: \(failure)" }
            else { self?.refreshFingerRecordings() }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let stateValue = activationState.rawValue
        let errorMessage = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.completeActivation(stateValue: stateValue, errorMessage: errorMessage)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.invalidateTVSession()
            self?.bridgeStatus = .switchingWatch
            self?.watchStatus = .checking
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self, let session = self.session else { return }
            self.invalidateTVSession()
            self.bridgeStatus = .starting
            session.activate()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.invalidateTVSession()
            self?.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }
}

extension PhoneRelayCoordinator {
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message["payload"] as? Data,
              let request = try? JSONDecoder().decode(VolumeBridgeMessage.self, from: data) else {
            replyHandler([:]); return
        }
        Task { @MainActor [weak self] in
            guard let self else { replyHandler([:]); return }
            let reply = await self.handle(request)
            replyHandler(["payload": (try? JSONEncoder().encode(reply)) ?? Data()])
        }
    }
}
