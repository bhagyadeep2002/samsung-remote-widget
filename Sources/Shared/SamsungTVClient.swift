import CryptoKit
import Foundation
import Security

enum SamsungTVClient {
    private static let pairingTimeout: TimeInterval = 45
    private static let commandTimeout: TimeInterval = 10

    static func pair(with hostInput: String) async throws {
        let host = try normalizedHost(hostInput)
        let existingPin = try PairingCredentialStore.certificatePin(for: host)
        let connection = try makeConnection(
            host: host,
            token: nil,
            certificatePin: existingPin,
            allowFirstUse: existingPin == nil
        )
        defer { connection.close() }

        SharedPreferences.saveStatus("Approve the connection request on your TV.")
        guard let token = try await waitForChannel(
            connection.task,
            timeout: pairingTimeout,
            pairing: true
        ),
        let certificatePin = connection.trustDelegate.observedFingerprint else {
            throw SamsungTVError.pairingDidNotReturnCredentials
        }

        try PairingCredentialStore.save(
            token: token,
            certificatePin: certificatePin,
            for: host
        )
        SharedPreferences.saveStatus("Paired. Add the Samsung TV Remote widget.")
    }

    static func send(_ key: SamsungRemoteKey) async throws {
        let host = try normalizedHost(SharedPreferences.host)
        guard let token = try PairingCredentialStore.token(for: host),
              let certificatePin = try PairingCredentialStore.certificatePin(for: host) else {
            throw SamsungTVError.notPaired
        }

        let connection = try makeConnection(
            host: host,
            token: token,
            certificatePin: certificatePin,
            allowFirstUse: false
        )
        defer { connection.close() }

        _ = try await waitForChannel(
            connection.task,
            timeout: commandTimeout,
            pairing: false
        )

        let payload: [String: Any] = [
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": key.samsungCode,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let message = String(data: data, encoding: .utf8) else {
            throw SamsungTVError.invalidCommand
        }
        try await connection.task.send(.string(message))
    }

    private static func makeConnection(
        host: String,
        token: String?,
        certificatePin: String?,
        allowFirstUse: Bool
    ) throws -> WebSocketConnection {
        let url = try remoteURL(host: host, token: token)
        let delegate = TVTrustDelegate(
            expectedFingerprint: certificatePin,
            allowFirstUse: allowFirstUse
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        let task = session.webSocketTask(with: URLRequest(url: url))
        task.resume()
        return WebSocketConnection(task: task, session: session, trustDelegate: delegate)
    }

    private static func remoteURL(host: String, token: String?) throws -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        components.queryItems = [
            URLQueryItem(
                name: "name",
                value: Data("Samsung TV Remote".utf8).base64EncodedString()
            )
        ]
        if let token {
            components.queryItems?.append(URLQueryItem(name: "token", value: token))
        }
        guard let url = components.url else {
            throw SamsungTVError.invalidAddress
        }
        return url
    }

    private static func normalizedHost(_ input: String) throws -> String {
        let host = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty,
              !host.contains("/"),
              !host.contains("://"),
              !host.contains("?") else {
            throw SamsungTVError.invalidAddress
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        guard components.url?.host != nil else {
            throw SamsungTVError.invalidAddress
        }
        return host
    }

    private static func waitForChannel(
        _ task: URLSessionWebSocketTask,
        timeout: TimeInterval,
        pairing: Bool
    ) async throws -> String? {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                try await receiveChannelToken(from: task, pairing: pairing)
            }
            group.addTask {
                let nanos = UInt64(timeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                task.cancel(with: .goingAway, reason: nil)
                throw SamsungTVError.connectionTimedOut
            }

            do {
                guard let value = try await group.next() else {
                    throw SamsungTVError.connectionTimedOut
                }
                group.cancelAll()
                return value
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private static func receiveChannelToken(
        from task: URLSessionWebSocketTask,
        pairing: Bool
    ) async throws -> String? {
        while true {
            let message = try await task.receive()
            guard case let .string(text) = message,
                  let data = text.data(using: .utf8),
                  let event = try? JSONDecoder().decode(ChannelEvent.self, from: data) else {
                continue
            }

            switch event.event {
            case "ms.channel.connect":
                if pairing && event.data?.token == nil {
                    throw SamsungTVError.pairingDidNotReturnCredentials
                }
                return event.data?.token
            case "ms.channel.unauthorized":
                if !pairing {
                    throw SamsungTVError.pairingRequired
                }
            case "ms.error":
                throw SamsungTVError.tvRejectedConnection
            default:
                continue
            }
        }
    }
}

private struct ChannelEvent: Decodable {
    struct EventData: Decodable {
        let token: String?
    }

    let event: String
    let data: EventData?
}

private struct WebSocketConnection {
    let task: URLSessionWebSocketTask
    let session: URLSession
    let trustDelegate: TVTrustDelegate

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

private final class TVTrustDelegate: NSObject, URLSessionDelegate {
    private let expectedFingerprint: String?
    private let allowFirstUse: Bool
    private let lock = NSLock()
    private var fingerprint: String?

    var observedFingerprint: String? {
        lock.lock()
        defer { lock.unlock() }
        return fingerprint
    }

    init(expectedFingerprint: String?, allowFirstUse: Bool) {
        self.expectedFingerprint = expectedFingerprint
        self.allowFirstUse = allowFirstUse
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let currentFingerprint = Self.fingerprint(for: certificate)
        let certificateMatches = expectedFingerprint == currentFingerprint
        // Samsung TVs use a self-signed certificate, so only the first pairing accepts an unknown pin.
        guard certificateMatches || (expectedFingerprint == nil && allowFirstUse) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        lock.lock()
        fingerprint = currentFingerprint
        lock.unlock()
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private static func fingerprint(for certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum SamsungTVError: LocalizedError {
    case invalidAddress
    case notPaired
    case pairingRequired
    case connectionTimedOut
    case pairingDidNotReturnCredentials
    case tvRejectedConnection
    case invalidCommand

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "Enter the TV's local IP address or network name."
        case .notPaired:
            "Pair with the TV in Samsung TV Remote first."
        case .pairingRequired:
            "The TV needs pairing approval. Open Samsung TV Remote and pair again."
        case .connectionTimedOut:
            "The TV did not respond. Check that it is on the same network and turned on."
        case .pairingDidNotReturnCredentials:
            "The TV connected without returning a pairing token. Try pairing again."
        case .tvRejectedConnection:
            "The TV rejected the connection. Check its network remote-control settings."
        case .invalidCommand:
            "The remote command could not be encoded."
        }
    }
}
