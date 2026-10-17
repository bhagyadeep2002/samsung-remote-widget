import Foundation

/// One authenticated socket is shared by warm-up, keepalive, and ordered commands.
protocol RemoteTransport: Sendable {
    func send(_ message: String) async throws
    func receive() async throws
    func ping() async throws
    func close()
}

struct RemoteCommandStep: Sendable {
    let message: String
    let delayAfter: Duration
}

actor PersistentRemoteConnection {
    private struct Connection {
        let id: UUID
        let transport: any RemoteTransport
    }

    private struct Attempt {
        let id: UUID
        let generation: UUID
        let task: Task<any RemoteTransport, Error>
    }

    private struct Command {
        let steps: [RemoteCommandStep]
        let host: String
        let generation: UUID
        let completion: CheckedContinuation<Void, Error>
    }

    private let connect: @Sendable (String) async throws -> any RemoteTransport
    private let keepaliveInterval: Duration
    private var host: String?
    private var generation = UUID()
    private var connection: Connection?
    private var attempt: Attempt?
    private var receiver: Task<Void, Never>?
    private var maintenance: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var commands: [Command] = []
    private var boundedWriteInFlight = false
    private let reconnectDuringMaintenance: Bool
    private let onDisconnect: @Sendable () -> Void

    init(
        keepaliveInterval: Duration = .seconds(15),
        reconnectDuringMaintenance: Bool = true,
        onDisconnect: @escaping @Sendable () -> Void = {},
        connect: @escaping @Sendable (String) async throws -> any RemoteTransport
    ) {
        self.keepaliveInterval = keepaliveInterval
        self.reconnectDuringMaintenance = reconnectDuringMaintenance
        self.onDisconnect = onDisconnect
        self.connect = connect
    }

    func prepare(host: String) async throws {
        selectHost(host)
        startMaintenance()
        _ = try await connected(to: host)
    }

    /// Pairing already produced an authenticated socket; keep using that socket.
    func adopt(_ transport: any RemoteTransport, host: String) {
        disconnect()
        self.host = host
        install(Connection(id: UUID(), transport: transport))
        startMaintenance()
    }

    func send(_ message: String, host: String) async throws {
        try await send([RemoteCommandStep(message: message, delayAfter: .zero)], host: host)
    }

    /// A batch stays on one connection and cannot interleave with another click.
    func send(_ steps: [RemoteCommandStep], host: String) async throws {
        guard !boundedWriteInFlight else { throw CancellationError() }
        selectHost(host)
        startMaintenance()
        try await withCheckedThrowingContinuation { completion in
            commands.append(Command(steps: steps, host: host, generation: generation, completion: completion))
            if worker == nil {
                worker = Task { await drainCommands() }
            }
        }
    }

    func isReady(host: String) -> Bool {
        self.host == host && connection != nil
    }

    /// Mobile volume has no queue and never waits for authentication/reconnection.
    func sendReady(_ message: String, host: String,
                   valid: @Sendable () -> Bool) async throws {
        guard self.host == host, let ready = connection,
              !boundedWriteInFlight, worker == nil, valid() else {
            throw CancellationError()
        }
        boundedWriteInFlight = true
        defer { boundedWriteInFlight = false }
        // No suspension between the final validity check and starting the write.
        do { try await ready.transport.send(message) }
        catch { invalidate(ready.id); throw error }
    }

    func disconnect() {
        onDisconnect()
        generation = UUID()
        host = nil
        attempt?.task.cancel()
        attempt = nil
        receiver?.cancel()
        receiver = nil
        connection?.transport.close()
        connection = nil
        maintenance?.cancel()
        maintenance = nil
        failQueuedCommands(with: CancellationError())
    }

    private func selectHost(_ host: String) {
        if self.host != host {
            disconnect()
            self.host = host
        }
    }

    private func connected(to host: String) async throws -> Connection {
        guard self.host == host else { throw CancellationError() }
        if let connection { return connection }

        let current: Attempt
        if let attempt {
            current = attempt
        } else {
            let connector = connect
            current = Attempt(id: UUID(), generation: generation, task: Task { try await connector(host) })
            attempt = current
        }

        do {
            let transport = try await current.task.value
            // A forgotten TV, a new address, or another connection must not be
            // replaced by the result of an older handshake that finished late.
            guard generation == current.generation, self.host == host,
                  attempt?.id == current.id || connection?.id == current.id else {
                transport.close()
                throw CancellationError()
            }
            if connection == nil {
                install(Connection(id: current.id, transport: transport))
            }
            if attempt?.id == current.id { attempt = nil }
            return Connection(id: current.id, transport: transport)
        } catch {
            if attempt?.id == current.id { attempt = nil }
            throw error
        }
    }

    private func install(_ connection: Connection) {
        self.connection = connection
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    try await connection.transport.receive()
                }
            } catch {
                await self?.invalidate(connection.id)
            }
        }
    }

    private func invalidate(_ id: UUID) {
        guard connection?.id == id else { return }
        onDisconnect()
        failQueuedCommands(with: CancellationError())
        connection?.transport.close()
        connection = nil
        receiver?.cancel()
        receiver = nil
    }

    private func drainCommands() async {
        while !commands.isEmpty {
            let command = commands.removeFirst()
            var usedConnection: Connection?
            do {
                let ready = try await connected(to: command.host)
                usedConnection = ready
                guard command.generation == generation else { throw CancellationError() }
                for step in command.steps {
                    guard command.generation == generation, connection?.id == ready.id else {
                        throw CancellationError()
                    }
                    try await ready.transport.send(step.message)
                    if step.delayAfter > .zero { try await Task.sleep(for: step.delayAfter) }
                }
                command.completion.resume()
            } catch {
                if let usedConnection { invalidate(usedConnection.id) }
                if command.generation == generation {
                    // A failed write may already have reached the TV. Never
                    // replay it, or let queued taps execute much later.
                    failQueuedCommands(with: error)
                }
                command.completion.resume(throwing: error)
            }
        }
        worker = nil
    }

    private func failQueuedCommands(with error: Error) {
        let pending = commands
        commands.removeAll()
        for command in pending { command.completion.resume(throwing: error) }
    }

    private func startMaintenance() {
        guard maintenance == nil else { return }
        let interval = keepaliveInterval
        let currentGeneration = generation
        maintenance = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                await self?.maintain(generation: currentGeneration)
            }
        }
    }

    private func maintain(generation: UUID) async {
        guard self.generation == generation, let host else { return }
        if !reconnectDuringMaintenance && connection == nil { return }
        var usedConnection: Connection?
        do {
            let ready = try await connected(to: host)
            usedConnection = ready
            try await ready.transport.ping()
        } catch {
            if let usedConnection { invalidate(usedConnection.id) }
            // The next tick reconnects if the TV was off or the network changed.
        }
    }
}
