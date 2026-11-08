import XCTest
import Network
@testable import NewZMud

@MainActor
private final class LocalGame {
    let listener: NWListener
    var clients: [NWConnection] = []
    var received = Data()
    var connectionCount = 0
    var greeting: Data
    private let queue = DispatchQueue(label: "NewZMudTests.server")

    init(greeting: Data = Data("Welcome\r\nName: ".utf8)) throws {
        self.greeting = greeting
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.listener.stateUpdateHandler = nil
                        continuation.resume()
                    case .failed(let error):
                        self.listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
        }
    }
    var port: UInt16 { listener.port!.rawValue }
    func send(_ data: Data) { clients.last?.send(content: data, completion: .contentProcessed { _ in }) }
    func closeClients() { for client in clients { client.cancel() }; clients.removeAll() }
    func stop() { closeClients(); listener.cancel() }
    func occurrences(_ text: String) -> Int { String(decoding: received, as: UTF8.self).components(separatedBy: text).count - 1 }

    private func accept(_ connection: NWConnection) {
        clients.append(connection); connectionCount += 1
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self, let connection else { return }
                if case .ready = state {
                    connection.send(content: self.greeting, completion: .contentProcessed { _ in })
                    self.read(connection)
                }
            }
        }
        connection.start(queue: queue)
    }
    private func read(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.received.append(data) }
                if !complete && error == nil { self.read(connection) }
            }
        }
    }
}

final class SessionTests: XCTestCase {
    @MainActor
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Local session condition timed out")
        throw NSError(domain: "NewZMudTests", code: 1)
    }

    @MainActor
    func testGMCPUpdatesCharacterAndAdvertisesClient() async throws {
        let greeting = Data([255, 251, 201])
            + TelnetStream.gmcp(#"Core.Hello {"mud_name":"Test world"}"#)
            + TelnetStream.gmcp(#"Char.Vitals {"hp":820,"max_hp":1000,"neili":360,"max_neili":500}"#)
            + TelnetStream.gmcp(#"Room.Info {"name":"扬州","exits":["north","east"]}"#)
        let server = try LocalGame(greeting: greeting)
        try await server.start()
        let session = MUDSession()
        defer { session.disconnect(announce: false); server.stop() }
        session.connect(host: "127.0.0.1", port: server.port)
        try await wait { session.character.room == "扬州" && server.occurrences("Char.Vitals.Get") > 0 }
        XCTAssertTrue(session.gmcpAvailable)
        XCTAssertEqual(session.character.health.current, 820)
        XCTAssertEqual(session.character.innerPower.maximum, 500)
        XCTAssertGreaterThan(server.occurrences("Core.Hello"), 0)
        XCTAssertGreaterThan(server.occurrences("Core.Supports.Set"), 0)
    }

    @MainActor
    func testAliasesTriggersAndTimersSendCommandsAndCanBeStopped() async throws {
        let server = try LocalGame()
        try await server.start()
        let session = MUDSession()
        defer { session.disconnect(announce: false); server.stop() }
        var settings = WorldConfiguration()
        settings.aliases = [AliasRule(name: "supplies", commands: "eat bread;drink water")]
        settings.triggers = [TriggerRule(pattern: "hungry", commands: "supplies")]
        settings.timers = [TimerRule(enabled: true, interval: 0.5, commands: "hp")]
        session.configure(settings)
        session.connect(host: "127.0.0.1", port: server.port)
        try await wait { session.isConnected }
        session.setAutomationEnabled(true)
        server.send(Data("\r\nYou are hungry.\r\n".utf8))
        try await wait { server.occurrences("eat bread\r\n") == 1 && server.occurrences("drink water\r\n") == 1 && server.occurrences("hp\r\n") >= 1 }
        session.stopAutomation()
        let count = server.occurrences("hp\r\n")
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(server.occurrences("hp\r\n"), count)
        XCTAssertFalse(session.automationEnabled)
    }

    @MainActor
    func testPasswordModeStopsAutomationAndDoesNotEchoSecrets() async throws {
        let server = try LocalGame()
        try await server.start()
        let session = MUDSession()
        defer { session.disconnect(announce: false); server.stop() }
        session.connect(host: "127.0.0.1", port: server.port)
        try await wait { session.isConnected }
        session.setAutomationEnabled(true)
        session.send("/walk 100n")
        try await wait { server.occurrences("n\r\n") > 0 }
        server.send(Data([255, 251, 1]))
        try await wait { session.isPasswordInput }
        XCTAssertFalse(session.automationEnabled)
        XCTAssertEqual(session.queuedCommands, 0)
        session.send("fixture-only-secret")
        try await wait { server.occurrences("fixture-only-secret\r\n") == 1 }
        XCTAssertFalse(session.terminal.plainText.contains("fixture-only-secret"))
        let steps = server.occurrences("n\r\n")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(server.occurrences("n\r\n"), steps)
    }

    @MainActor
    func testUnexpectedDisconnectReconnectsWithoutReplayingCommands() async throws {
        let server = try LocalGame()
        try await server.start()
        let session = MUDSession()
        defer { session.disconnect(announce: false); server.stop() }
        var settings = WorldConfiguration()
        settings.autoReconnect = true
        session.configure(settings)
        session.connect(host: "127.0.0.1", port: server.port)
        try await wait { session.isConnected }
        session.send("look")
        try await wait { server.occurrences("look\r\n") == 1 }
        server.closeClients()
        try await wait { session.reconnectIn != nil }
        try await wait { server.connectionCount == 2 && session.isConnected }
        XCTAssertEqual(server.occurrences("look\r\n"), 1)
        XCTAssertFalse(session.automationEnabled)
    }

    @MainActor
    func testManualReconnectKeepsTranscriptAndReopensSelectedEndpoint() async throws {
        let server = try LocalGame(greeting: Data("Welcome back\r\nName: ".utf8))
        try await server.start()
        let session = MUDSession()
        defer { session.disconnect(announce: false); server.stop() }
        session.connect(host: "127.0.0.1", port: server.port)
        try await wait { session.terminal.plainText.contains("Name:") }
        server.closeClients()
        try await wait { session.canReconnect }
        XCTAssertTrue(session.terminal.plainText.contains("Welcome back"))

        session.reconnectNow()
        try await wait { server.connectionCount == 2 && session.isConnected }
        XCTAssertTrue(session.terminal.plainText.contains("Welcome back"))
        XCTAssertTrue(session.terminal.plainText.contains("Name:"))
    }
}
