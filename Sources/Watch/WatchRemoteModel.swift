import Combine
import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class WatchRemoteModel: NSObject, ObservableObject {
    enum BridgeStatus: Equatable {
        case unsupported
        case starting
        case active
        case failed(String)

        var title: String {
            switch self {
            case .unsupported: "Watch Connectivity unavailable"
            case .starting: "Starting"
            case .active: "Active"
            case let .failed(message): "Activation failed: \(message)"
            }
        }

        var detail: String {
            switch self {
            case .unsupported:
                "This Watch cannot connect to the iPhone relay."
            case .starting:
                "Waiting for Watch Connectivity to activate."
            case .active:
                "The Watch bridge is active. TV readiness is shown separately."
            case .failed:
                "The Watch bridge did not activate. Reopen this app to retry."
            }
        }

        var symbolName: String {
            switch self {
            case .unsupported, .failed: "xmark.circle"
            case .starting: "arrow.triangle.2.circlepath"
            case .active: "checkmark.circle"
            }
        }
    }

    let fingerCapture = FingerCaptureController()
    private var captureObservation: AnyCancellable?
    @Published private(set) var recordingTransferStatus = ""
    @Published private var motionAdmission = WatchMotionAdmission()
    private var motionSequence = 0

    @Published private(set) var bridgeStatus: BridgeStatus = .starting
    @Published private(set) var phoneStatus = "Checking for the iPhone app…"

    @Published private(set) var tvStatus = "Connect to your TV through iPhone."
    @Published private(set) var latencyStatus: String?
    @Published private var admission = WatchVolumeAdmission()
    var isConnected: Bool { admission.sessionID != nil }
    var canSend: Bool { foreground && isConnected && !sending && !fingerCapture.isRecording && motionAdmission.canRefresh }
    var canRecordFingerGesture: Bool {
        foreground && !sending && (fingerCapture.mode != .control || (isConnected && motionAdmission.canRefresh))
    }
    @Published private(set) var sending = false
    @Published private(set) var connecting = false
    private var foreground = false
    private var generation = UUID()
    private var nextTap: TimeInterval = 0
    private var sequence = 0
    private var heartbeat: Task<Void, Never>?
    private var session: WCSession?
    private var didActivate = false

    override init() {
        super.init()
        captureObservation = fingerCapture.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        fingerCapture.onLiveBegin = { [weak self] id in self?.beginMotion(generation: id) }
        fingerCapture.onLiveIntent = { [weak self] intent in self?.sendMotion(intent) }
        fingerCapture.onLiveEnd = { [weak self] id in self?.endMotion(generation: id) }
    }

    func beginFingerCapture() {
        guard canRecordFingerGesture else { return }
        fingerCapture.begin()
    }

    func sendFingerRecordings() {
        guard !fingerCapture.isRecording, let session, session.activationState == .activated else {
            recordingTransferStatus = "Open the iPhone app and try again."; return
        }
        let files = FingerRecordingStore().recordings
        guard !files.isEmpty else { recordingTransferStatus = "Record a few examples first."; return }
        let pending = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for file in files where !pending.contains(file.lastPathComponent) {
            session.transferFile(file, metadata: ["kind": FingerRecordingStore.transferKind])
        }
        recordingTransferStatus = "Queued \(files.count) saved trials. Check the iPhone for received recordings."
    }

    func clearFingerRecordings() {
        guard !fingerCapture.isRecording else { return }
        session?.outstandingFileTransfers.filter {
            $0.file.metadata?["kind"] as? String == FingerRecordingStore.transferKind
        }.forEach { $0.cancel() }
        do {
            try FingerRecordingStore().removeAll()
            fingerCapture.refreshCounts()
            recordingTransferStatus = "Watch recordings cleared."
        } catch { recordingTransferStatus = error.localizedDescription }
    }

    private func beginMotion(generation id: UUID) {
        guard foreground, fingerCapture.isLiveHeld(generation: id), !sending, let session,
              session.isReachable, let remote = admission.sessionID else {
            fingerCapture.cancel(reason: "Connect to start motion."); return
        }
        motionSequence += 1
        let activation = MotionActivation(sessionID: remote, generation: id, sequence: motionSequence)
        admission.discardPermit(at: now)
        motionAdmission.begin(activation)
        fingerCapture.deliveryStatus = "Preparing volume link…"
        let started = now
        Task {
            do {
                let reply = try await VolumeBridgeWire.send(
                    VolumeBridgeMessage(kind: "motionBegin", sessionID: remote,
                        activationID: activation.id, activationSequence: activation.sequence), session: session,
                    validity: { [weak self] in self?.motionAdmission.isCurrent(activation) == true })
                guard motionAdmission.isCurrent(activation), foreground else { return }
                guard reply.status == "ready" else {
                    fingerCapture.cancel(reason: "Volume link not ready. Release and hold again."); return
                }
                motionAdmission.receive(reply, for: activation, requestStarted: started)
                guard motionAdmission.ready else {
                    fingerCapture.cancel(reason: "Invalid volume-link reply. Release and hold again."); return
                }
                fingerCapture.deliveryStatus = "Volume link ready"
                fingerCapture.volumeLinkReady(generation: id)
            } catch {
                guard motionAdmission.isCurrent(activation) else { return }
                fingerCapture.cancel(reason: "Volume link unavailable. Release and hold again.")
            }
        }
    }

    private func endMotion(generation id: UUID) {
        guard let activation = motionAdmission.activation, activation.generation == id else { return }
        _ = motionAdmission.cancel()
        fingerCapture.deliveryStatus = "Motion stopped"
        guard let session, session.isReachable else {
            motionAdmission.finishEnd(activation)
            return
        }
        Task {
            defer { motionAdmission.finishEnd(activation) }
            _ = try? await VolumeBridgeWire.send(
                VolumeBridgeMessage(kind: "motionEnd", sessionID: activation.sessionID,
                    activationID: activation.id, activationSequence: activation.sequence), session: session)
        }
    }

    private func sendMotion(_ intent: TwistIntent) {
        guard foreground, fingerCapture.isLiveHeld(generation: intent.generation),
              let session, session.isReachable else { return }
        guard !sending else {
            fingerCapture.deliveryStatus = "Command skipped: link busy. Release and hold again."; return
        }
        guard let (activation, permit) = motionAdmission.take(for: intent.generation,
                timestamp: intent.timestamp, now: now) else {
            fingerCapture.deliveryStatus = "Gesture skipped: waiting for a fresh link permit."
            return
        }
        sending = true
        sequence += 1
        let foregroundGeneration = generation
        let request = VolumeBridgeMessage(kind: "motionStep", sessionID: activation.sessionID,
            permitID: permit, activationID: activation.id, activationSequence: activation.sequence,
            sequence: sequence, direction: intent.direction.rawValue)
        Task {
            defer { if generation == foregroundGeneration { sending = false } }
            do {
                let reply = try await VolumeBridgeWire.send(request, session: session, validity: { [weak self] in
                    guard let self else { return false }
                    return self.foreground && self.fingerCapture.isLiveHeld(generation: intent.generation) &&
                        self.motionAdmission.valid(activation, generation: intent.generation,
                            timestamp: intent.timestamp, now: self.now)
                })
                guard motionAdmission.isCurrent(activation), foreground else { return }
                switch reply.status {
                case "sentToSocket": fingerCapture.deliveryStatus = "Command sent; TV response unconfirmed."
                case "expired", "cancelled": fingerCapture.deliveryStatus = "Gesture expired; not retried."
                default: fingerCapture.cancel(reason: "Send outcome unknown. Release and hold again.")
                }
            } catch is CancellationError {
                // Pause/inactivity cancelled an unsent step. Nothing is replayed.
            } catch {
                guard motionAdmission.isCurrent(activation) else { return }
                fingerCapture.cancel(reason: "Send outcome unknown. Release and hold again.")
            }
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
            phoneStatus = "Watch Connectivity is not supported on this device."
            return
        }

        let session = WCSession.default
        session.delegate = self
        self.session = session
        bridgeStatus = .starting
        session.activate()
        refresh()
    }

    func refresh() {
        guard let session else { return }

        switch session.activationState {
        case .notActivated:
            if isConnected || connecting { stop(reason: "iPhone bridge is inactive. Connect again.") }
            bridgeStatus = .starting
            phoneStatus = "Waiting for Watch Connectivity to activate."
        case .inactive:
            if isConnected || connecting { stop(reason: "iPhone bridge is inactive. Connect again.") }
            bridgeStatus = .starting
            phoneStatus = "The Watch session is inactive."
        case .activated:
            bridgeStatus = .active
            refreshPhoneStatus(using: session)
        @unknown default:
            bridgeStatus = .starting
            phoneStatus = "Checking the paired iPhone."
        }
    }

    private func refreshPhoneStatus(using session: WCSession) {
        guard session.isCompanionAppInstalled else {
            if isConnected || connecting { stop(reason: "iPhone app is unavailable.") }
            phoneStatus = "Install the iPhone app to use this Watch remote."
            return
        }
        if !session.isReachable && (isConnected || connecting) { stop(reason: "iPhone connection lost. Connect again.") }
        phoneStatus = session.isReachable
            ? "The iPhone app is reachable."
            : "Open the iPhone app to make the live bridge reachable."
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func setForeground(_ value: Bool) {
        foreground = value
        if !value { fingerCapture.cancel(reason: "Watch inactive. Trial discarded.") }
        if value {
            activate()
            connect()
        } else if isConnected || connecting || sending {
            stop(reason: "Watch paused. Connect again when active.")
        }
    }

    func stop(reason: String = "Connect to your TV through iPhone.") {
        fingerCapture.cancel(reason: "Connection stopped. Trial discarded.")
        motionAdmission.reset()
        let oldSession = admission.sessionID
        generation = UUID()
        admission.end()
        connecting = false
        sending = false
        heartbeat?.cancel()
        heartbeat = nil
        tvStatus = reason
        if let oldSession, let session, session.isReachable {
            Task { _ = try? await VolumeBridgeWire.send(
                VolumeBridgeMessage(kind: "end", sessionID: oldSession), session: session) }
        }
    }

    func connect() {
        guard foreground, !connecting, admission.sessionID == nil,
              let session, session.activationState == .activated, session.isReachable else { return }
        connecting = true
        tvStatus = "Connecting to TV…"
        let current = generation
        Task {
            do {
                let started = now
                let reply = try await VolumeBridgeWire.send(VolumeBridgeMessage(kind: "prepare"), session: session)
                guard generation == current, foreground else { return }
                connecting = false
                guard reply.status == "ready", let id = reply.sessionID else {
                    tvStatus = reply.detail ?? "Pair with the TV on your iPhone first."
                    return
                }
                admission.connect(session: id)
                sequence = 0
                motionSequence = 0
                admission.receivePermit(reply.permitID, session: id, requestStarted: started)
                tvStatus = "TV connection ready"
                startHeartbeat(session: session, id: id, generation: current, lastRequestStarted: started)
                // Connecting never starts sensing; the user must explicitly hold.
            } catch {
                guard generation == current else { return }
                connecting = false
                tvStatus = "Cannot reach iPhone. Open its app and connect again."
            }
        }
    }

    private func startHeartbeat(session: WCSession, id: String, generation current: UUID,
                                lastRequestStarted: TimeInterval) {
        heartbeat?.cancel()
        heartbeat = Task {
            var previousStart = lastRequestStarted
            while !Task.isCancelled, foreground, generation == current {
                do {
                    // Begin must be acknowledged before a scoped heartbeat can
                    // overtake it and look like an invalid remote activation.
                    if !motionAdmission.canRefresh {
                        try await Task.sleep(for: .milliseconds(50))
                        continue
                    }
                    let delay = VolumeBridgeTiming.refreshDelay(requestStarted: previousStart, now: now)
                    if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                    guard !Task.isCancelled, generation == current else { return }
                    let started = now
                    previousStart = started
                    let activation = motionAdmission.activation
                    let scopeSequence = motionSequence
                    let reply = try await VolumeBridgeWire.send(
                        VolumeBridgeMessage(kind: "heartbeat", sessionID: id,
                            activationID: activation?.id, activationSequence: activation?.sequence), session: session)
                    guard generation == current, foreground else { return }
                    // A heartbeat from before pause/recalibration cannot affect
                    // the new activation, even when it reports notReady.
                    guard motionAdmission.activation == activation, motionSequence == scopeSequence else { continue }
                    guard reply.status == "ready" else {
                        stop(reason: reply.detail ?? "TV disconnected. Connect again.")
                        return
                    }
                    if let activation {
                        motionAdmission.receive(reply, for: activation, requestStarted: started)
                    } else {
                        admission.receivePermit(reply.permitID, session: id, requestStarted: started)
                    }
                } catch {
                    guard generation == current else { return }
                    stop(reason: "iPhone unavailable. Connect again.")
                    return
                }
            }
        }
    }

    func volume(up: Bool) {
        guard canSend, now >= nextTap, let id = admission.sessionID,
              let session, session.isReachable else { return }
        sending = true
        let tapped = now
        nextTap = tapped + 0.125
        let current = generation
        Task {
            defer { if generation == current { sending = false } }
            do {
                var permitMilliseconds = 0
                var permit = admission.takePermit(now: now)
                if permit == nil {
                    // This tap has never been transmitted. Obtain a permit once;
                    // the tap's original local deadline is never extended.
                    let reply = try await VolumeBridgeWire.send(
                        VolumeBridgeMessage(kind: "heartbeat", sessionID: id), session: session)
                    guard generation == current, foreground else { return }
                    guard reply.status == "ready", reply.sessionID == id else {
                        stop(reason: reply.detail ?? "TV disconnected. Connect again.")
                        return
                    }
                    permitMilliseconds = Int(((now - tapped) * 1000).rounded())
                    admission.receivePermit(reply.permitID, session: id, requestStarted: tapped)
                    permit = admission.takePermit(now: now)
                }
                guard generation == current, foreground, admission.sessionID == id else { return }
                guard let permit, WatchVolumeAdmission.freshTap(started: tapped, now: now) else {
                    let milliseconds = Int((now - tapped) * 1000)
                    tvStatus = "Tap expired (\(milliseconds) ms). No command sent."
                    return
                }
                sequence += 1
                let request = VolumeBridgeMessage(kind: "step", sessionID: id, permitID: permit,
                                                  sequence: sequence, direction: up ? "up" : "down")
                let reply = try await VolumeBridgeWire.send(request, session: session)
                guard generation == current, foreground else { return }
                let elapsed = Int(((now - tapped) * 1000).rounded())
                var timing = "Last tap reply: \(elapsed) ms"
                if let relay = reply.relayMilliseconds, relay.isFinite, relay >= 0, relay < 60_000 {
                    timing += "\niPhone send: \(Int(relay.rounded())) ms"
                }
                if permitMilliseconds > 0 {
                    timing += "\nPermit request: \(permitMilliseconds) ms"
                }
                latencyStatus = timing
                switch reply.status {
                case "sentToSocket": tvStatus = "Command sent; TV response unconfirmed."
                case "expired", "cancelled": tvStatus = "Tap expired. No retry was sent."
                default:
                    stop(reason: "Send outcome unknown. Connect again; tap was not retried.")
                }
            } catch {
                guard generation == current else { return }
                stop(reason: "Request failed. Outcome unknown if sent; tap was not retried.")
            }
        }
    }

    private func completeActivation(stateValue: Int, errorMessage: String?) {
        let state = WCSessionActivationState(rawValue: stateValue) ?? .notActivated
        if let errorMessage, state != .activated {
            bridgeStatus = .failed(errorMessage)
            phoneStatus = "Check the paired iPhone and try again."
            return
        }
        refresh()
        if foreground { connect() }
    }
}

extension WatchRemoteModel: WCSessionDelegate {
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

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            if !session.isReachable { self?.fingerCapture.cancel(reason: "iPhone disconnected. Trial discarded.") }
            self?.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard fileTransfer.file.metadata?["kind"] as? String == FingerRecordingStore.transferKind else { return }
        let failure = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.recordingTransferStatus = failure.map { "Transfer failed: \($0). Saved trials remain on Watch; send again." }
                ?? "A trial was delivered to iPhone. Check its received counts before exporting."
        }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }
}
