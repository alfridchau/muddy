import Foundation
import Network

@MainActor
final class MUDSession: ObservableObject {
    @Published private(set) var terminal = TerminalBuffer()
    @Published private(set) var character = CharacterState()
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isPasswordInput = false
    @Published private(set) var gmcpAvailable = false
    @Published private(set) var automationEnabled = false
    @Published private(set) var queuedCommands = 0
    @Published private(set) var reconnectIn: Int?
    @Published private(set) var status = "Not connected"

    var lines: [String] { terminal.plainLines }
    var canCancelConnection: Bool { isConnected || isConnecting || reconnectIn != nil }
    var canReconnect: Bool { endpoint != nil && !isConnected && !isConnecting && reconnectIn == nil }
    private var connection: NWConnection?
    private let networkQueue = DispatchQueue(label: "NewZMud.network")
    private var stream = TelnetStream()
    private var configuration = WorldConfiguration()
    private var endpoint: (host: String, port: UInt16)?
    private var timeoutTask: Task<Void, Never>?
    private var stableConnectionTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var vitalsTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var commandGeneration = UUID()
    private var timerTasks: [UUID: Task<Void, Never>] = [:]
    private var commands: [(text: String, delay: Double)] = []
    private var lastTriggered: [UUID: Date] = [:]
    private var retryAttempt = 0
    private var terminalColumns = 80
    private var terminalRows = 30

    func configure(_ configuration: WorldConfiguration) {
        self.configuration = configuration
        if !configuration.autoReconnect, reconnectIn != nil {
            retryTask?.cancel(); retryTask = nil; reconnectIn = nil
            status = "Disconnected. Click Connect to retry."
        }
        if automationEnabled { startTimers() }
    }

    func connect(host: String, port: UInt16) {
        guard !host.isEmpty, port > 0 else { notice("Enter a valid hostname and port."); return }
        disconnect(announce: false)
        endpoint = (host, port)
        retryAttempt = 0
        terminal.clear()
        openConnection()
    }

    private func openConnection() {
        guard let endpoint, let port = NWEndpoint.Port(rawValue: endpoint.port) else { return }
        closeTransport()
        character = CharacterState()
        isConnecting = true
        status = "Connecting to \(endpoint.host):\(endpoint.port)…"
        notice(status)
        let next = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        connection = next
        next.stateUpdateHandler = { [weak self, weak next] state in
            Task { @MainActor in
                guard let self, let next, self.connection === next else { return }
                switch state {
                case .ready:
                    self.timeoutTask?.cancel()
                    self.isConnecting = false; self.isConnected = true
                    // An accept-and-close loop must still exhaust the retry budget.
                    self.stableConnectionTask = Task { [weak self, weak next] in
                        do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                        guard let self, let next, self.connection === next else { return }
                        self.retryAttempt = 0
                    }
                    self.status = "Connected to \(endpoint.host):\(endpoint.port)"
                    self.notice(self.status)
                    self.receive(from: next)
                case .failed(let error): self.connectionLost("Connection failed: \(error.localizedDescription)")
                case .waiting: self.status = "Waiting for \(endpoint.host)…"
                case .cancelled: self.connectionLost("Connection cancelled.")
                default: break
                }
            }
        }
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            guard let self, self.isConnecting else { return }
            self.connectionLost("Connection timed out. Check the host and port.")
        }
        next.start(queue: networkQueue)
    }

    func disconnect(announce: Bool = true) {
        retryTask?.cancel(); retryTask = nil; reconnectIn = nil
        endpoint = nil
        closeTransport()
        status = "Not connected"
        if announce { notice("Disconnected.") }
    }

    /// Reopens the last endpoint, preserving the transcript for context.
    func reconnectNow() {
        guard endpoint != nil else { return }
        retryTask?.cancel(); retryTask = nil; reconnectIn = nil
        retryAttempt = 0
        openConnection()
    }

    private func closeTransport() {
        timeoutTask?.cancel(); timeoutTask = nil
        stableConnectionTask?.cancel(); stableConnectionTask = nil
        vitalsTask?.cancel(); vitalsTask = nil
        stopAutomation()
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        isConnected = false; isConnecting = false; isPasswordInput = false
        gmcpAvailable = false
        stream = TelnetStream()
        _ = stream.resize(columns: terminalColumns, rows: terminalRows)
    }

    private func connectionLost(_ message: String) {
        closeTransport()
        status = message
        notice(message)
        guard configuration.autoReconnect, endpoint != nil else { return }
        retryAttempt += 1
        guard let delay = ReconnectPolicy.delay(for: retryAttempt) else {
            status = "Reconnect attempts exhausted. Click Connect to retry."
            notice(status)
            return
        }
        reconnectIn = delay
        retryTask = Task { [weak self] in
            for seconds in stride(from: delay, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.reconnectIn = seconds
                self.status = "Reconnecting in \(seconds)s · attempt \(self.retryAttempt) of 5"
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.reconnectIn = nil
            self.openConnection()
        }
    }

    func clearOutput() { terminal.clear() }
    func reset() { disconnect(announce: false); terminal.clear(); character = CharacterState() }

    func resize(columns: Int, rows: Int) {
        guard columns != terminalColumns || rows != terminalRows else { return }
        terminalColumns = columns; terminalRows = rows
        terminal.resize(columns: columns, rows: rows)
        write(stream.resize(columns: columns, rows: rows))
    }

    /// Password replies bypass aliases, queues, echo, and history handling.
    func send(_ command: String) {
        guard isConnected else { return }
        if isPasswordInput { sendRaw(command); return }
        if command == "/stop" { stopAutomation(); notice("Automation and queued commands stopped."); return }
        do {
            let expanded = try CommandExpansion.aliases(command, rules: configuration.aliases)
            if expanded.isEmpty && command.isEmpty { sendRaw(""); return }
            try enqueue(expanded)
        } catch { notice(error.localizedDescription) }
    }

    func setAutomationEnabled(_ enabled: Bool) {
        guard enabled else { stopAutomation(); return }
        guard isConnected, !isPasswordInput else { return }
        automationEnabled = true
        lastTriggered.removeAll()
        startTimers()
        notice("Triggers and timers enabled for this session. /stop pauses automation.")
    }

    func stopAutomation() {
        automationEnabled = false
        commandGeneration = UUID()
        commandTask?.cancel(); commandTask = nil
        for task in timerTasks.values { task.cancel() }
        timerTasks.removeAll(); commands.removeAll(); queuedCommands = 0
    }

    private func enqueue(_ source: [String]) throws {
        guard isConnected, !isPasswordInput else { return }
        var planned: [(text: String, delay: Double)] = []
        for item in source {
            if item.hasPrefix("/walk ") {
                let path = String(item.dropFirst(6))
                planned += try CommandExpansion.walk(path).map { ($0, max(0.1, min(10, configuration.walkDelay))) }
            } else if item == "/walk" { throw CommandExpansionError.invalidPath }
            else if item == "/stop" { stopAutomation(); return }
            else { planned.append((item, 0.15)) }
            guard planned.count + commands.count <= 100 else { throw CommandExpansionError.tooManyCommands }
        }
        commands += planned
        queuedCommands = commands.count
        guard commandTask == nil else { return }
        let generation = UUID()
        commandGeneration = generation
        commandTask = Task { [weak self] in
            while let self, self.commandGeneration == generation, !Task.isCancelled, self.isConnected, !self.isPasswordInput, !self.commands.isEmpty {
                let next = self.commands.removeFirst()
                self.queuedCommands = self.commands.count
                self.sendRaw(next.text)
                do { try await Task.sleep(nanoseconds: UInt64(next.delay * 1_000_000_000)) } catch { return }
            }
            if self?.commandGeneration == generation { self?.commandTask = nil }
        }
    }

    private func startTimers() {
        for task in timerTasks.values { task.cancel() }
        timerTasks.removeAll()
        for timer in configuration.timers where timer.enabled && !timer.commands.isEmpty && timer.interval.isFinite {
            let interval = max(0.5, min(86_400, timer.interval))
            timerTasks[timer.id] = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) } catch { return }
                    guard let self, self.automationEnabled, self.isConnected, !self.isPasswordInput else { return }
                    self.runActions(timer.commands)
                }
            }
        }
    }

    private func runActions(_ source: String) {
        do { try enqueue(CommandExpansion.aliases(source, rules: configuration.aliases)) }
        catch { notice(error.localizedDescription); stopAutomation() }
    }

    private func processTriggers(_ lines: [String]) {
        guard automationEnabled, !isPasswordInput else { return }
        for line in lines {
            for rule in configuration.triggers where rule.enabled {
                if let last = lastTriggered[rule.id], Date().timeIntervalSince(last) < 1 { continue }
                if let actions = CommandExpansion.trigger(rule, line: line) {
                    lastTriggered[rule.id] = Date()
                    runActions(actions.joined(separator: "\n"))
                }
            }
        }
    }

    private func sendRaw(_ command: String) {
        guard isConnected else { return }
        // Keep command text literal; game input must not be interpreted as ANSI.
        let visible = command.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(String.init).joined()
        display((isPasswordInput ? "" : visible) + "\r\n")
        write(Data((command + "\r\n").utf8))
    }

    private func write(_ data: Data) {
        guard !data.isEmpty, let connection, isConnected else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
            if let error {
                Task { @MainActor in
                    guard let self, let connection, self.connection === connection else { return }
                    self.connectionLost("Send failed: \(error.localizedDescription)")
                }
            }
        })
    }

    private func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                if let data, !data.isEmpty {
                    let output = self.stream.receive(data)
                    self.write(output.reply)
                    if let password = output.passwordInput {
                        self.isPasswordInput = password
                        if password { self.stopAutomation() }
                    }
                    if let enabled = output.gmcpEnabled {
                        self.gmcpAvailable = enabled
                        if enabled {
                            self.write(TelnetStream.gmcp(#"Core.Hello {"client":"NewZMud","version":"0.2"}"#))
                            self.write(TelnetStream.gmcp(#"Core.Supports.Set ["Char 1","Char.Vitals 1","Room 1"]"#))
                            self.startVitalsPolling()
                        }
                    }
                    for message in output.messages { self.receiveGMCP(message) }
                    let completed = self.display(output.terminalText)
                    self.processTriggers(completed)
                }
                if let error { self.connectionLost("Connection error: \(error.localizedDescription)") }
                else if complete { self.connectionLost("The server closed the connection.") }
                else { self.receive(from: connection) }
            }
        }
    }

    private func receiveGMCP(_ message: GMCPMessage) {
        character.receive(message)
        if message.module == "Room.Info" || message.module == "Char.Vitals" {
            startVitalsPolling()
        }
    }

    private func startVitalsPolling() {
        guard vitalsTask == nil else { return }
        vitalsTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isConnected {
                if self.gmcpAvailable && !self.isPasswordInput {
                    self.write(TelnetStream.gmcp("Char.Vitals.Get"))
                }
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            }
        }
    }

    private func notice(_ message: String) {
        // Notices deliberately start a fresh line and reset color.
        display("\r\n\u{1B}[0;90m\(message)\u{1B}[0m\r\n")
    }

    @discardableResult
    private func display(_ text: String) -> [String] {
        var updated = terminal
        let completed = updated.feed(text)
        terminal = updated
        return completed
    }
}
