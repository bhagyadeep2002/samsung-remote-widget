import Foundation

enum TVRemoteAction: Sendable {
    case key(SamsungRemoteKey)
    case showNumberPad
    case hideNumberPad
    case restartNumberPad
    case deleteNumber
    case finishNumberEntry
}

struct TVRemoteStep: Sendable {
    let key: SamsungRemoteKey
    let delayAfter: Duration

    init(_ key: SamsungRemoteKey, delayAfter: Duration = .milliseconds(60)) {
        self.key = key
        self.delayAfter = delayAfter
    }
}

/// Layout from this TV: 1 2 3 4 5 [6] 7 8 9 0 Delete, with Done above.
/// Cursor tracking is a prediction: the TV does not report its focused button.
struct TVNumberPadNavigation {
    private(set) var cursor: Int?
    private(set) var needsRestart = false

    mutating func invalidate() {
        needsRestart = true
    }

    mutating func steps(for action: TVRemoteAction) throws -> [TVRemoteStep] {
        if needsRestart {
            switch action {
            case .restartNumberPad, .hideNumberPad: break
            case let .key(key) where key.digit == nil && key != .numberPad: break
            default: throw TVNumberPadError.outOfSync
            }
        }
        switch action {
        case .showNumberPad, .key(.numberPad):
            return openIfNeeded()
        case .restartNumberPad:
            // Explicit recovery also handles an overlay moved by the physical remote.
            cursor = nil
            needsRestart = false
            let closing = [TVRemoteStep(.back, delayAfter: .milliseconds(150))]
            return closing + openIfNeeded()
        case .hideNumberPad:
            return closeIfNeeded()
        case .deleteNumber:
            let opening = openIfNeeded()
            return opening + selectColumn(10)
        case .finishNumberEntry:
            guard cursor != nil else { throw TVNumberPadError.notOpen }
            cursor = nil
            return [TVRemoteStep(.up), TVRemoteStep(.select, delayAfter: .milliseconds(150))]
        case let .key(key):
            if let digit = key.digit {
                let opening = openIfNeeded()
                return opening + selectColumn(digit == 0 ? 9 : digit - 1)
            }
            switch key {
            case .back, .home, .powerOff:
                cursor = nil
                needsRestart = false
                return [TVRemoteStep(key, delayAfter: .zero)]
            default:
                // Other controls can dismiss or change the TV's overlay.
                return closeIfNeeded() + [TVRemoteStep(key, delayAfter: .zero)]
            }
        }
    }

    private mutating func openIfNeeded() -> [TVRemoteStep] {
        guard cursor == nil else { return [] }
        cursor = 5 // The photo shows 6 selected on opening.
        return [TVRemoteStep(.numberPad, delayAfter: .milliseconds(400))]
    }

    private mutating func closeIfNeeded() -> [TVRemoteStep] {
        guard cursor != nil || needsRestart else { return [] }
        cursor = nil
        needsRestart = false
        return [TVRemoteStep(.back, delayAfter: .milliseconds(150))]
    }

    private mutating func selectColumn(_ target: Int) -> [TVRemoteStep] {
        let distance = target - (cursor ?? 5)
        let direction: SamsungRemoteKey = distance < 0 ? .left : .right
        cursor = target
        return Array(repeating: TVRemoteStep(direction), count: abs(distance))
            + [TVRemoteStep(.select, delayAfter: .milliseconds(100))]
    }
}

enum TVNumberPadError: LocalizedError {
    case notOpen
    case outOfSync

    var errorDescription: String? {
        switch self {
        case .notOpen: "Open the number pad and enter a number before choosing Done."
        case .outOfSync: "Number entry was interrupted. Choose Restart to reopen the TV’s number pad before entering more digits."
        }
    }
}

/// Plans and completes one whole keypad operation before planning the next.
/// This preserves cursor state even when the user clicks several digits quickly.
actor TVRemoteControlSession {
    private struct Request {
        let action: TVRemoteAction
        let generation: UUID
        let completion: CheckedContinuation<Void, Error>
    }

    private let send: @Sendable ([TVRemoteStep]) async throws -> Void
    private var navigation = TVNumberPadNavigation()
    private var generation = UUID()
    private var requests: [Request] = []
    private var worker: Task<Void, Never>?

    init(send: @escaping @Sendable ([TVRemoteStep]) async throws -> Void) {
        self.send = send
    }

    func perform(_ action: TVRemoteAction) async throws {
        try await withCheckedThrowingContinuation { completion in
            requests.append(Request(action: action, generation: generation, completion: completion))
            if worker == nil { worker = Task { await drain() } }
        }
    }

    func reset() {
        generation = UUID()
        navigation = TVNumberPadNavigation()
        failPending(CancellationError())
    }

    private func drain() async {
        while !requests.isEmpty {
            let request = requests.removeFirst()
            var next = navigation
            do {
                let steps = try next.steps(for: request.action)
                if !steps.isEmpty { try await send(steps) }
                guard request.generation == generation else { throw CancellationError() }
                navigation = next
                request.completion.resume()
            } catch {
                if request.generation == generation {
                    if navigation.cursor != nil || next.cursor != nil { navigation.invalidate() }
                    failPending(error)
                }
                request.completion.resume(throwing: error)
            }
        }
        worker = nil
    }

    private func failPending(_ error: Error) {
        let pending = requests
        requests.removeAll()
        for request in pending { request.completion.resume(throwing: error) }
    }
}
