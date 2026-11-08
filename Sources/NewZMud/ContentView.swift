import SwiftUI

struct ContentView: View {
    @StateObject private var library = WorldLibrary()
    @StateObject private var session = MUDSession()
    @StateObject private var automation = AutomationStore()
    @AppStorage("selectedWorldID") private var selectionID = World.demo.id.uuidString
    @State private var editingWorld: World?
    @State private var showInspector = true
    @State private var command = ""
    @State private var history: [String] = []
    @State private var showHistory = false
    @State private var search = ""
    @State private var showSearch = false
    @State private var demoLines = DemoWorld.introduction
    @AppStorage("terminalFontSize") private var fontSize: Double = 14
    @State private var focusRequest = 0
    @State private var showAutomation = false
    @State private var followingOutput = true
    @State private var pendingOutput = 0
    @State private var terminalColumns = 80
    @State private var terminalRows = 30

    private var selection: UUID { UUID(uuidString: selectionID) ?? World.demo.id }
    private var world: World { library.worlds.first { $0.id == selection } ?? .demo }
    private var displayBuffer: TerminalBuffer {
        guard world.isDemo else { return session.terminal }
        var buffer = TerminalBuffer()
        buffer.resize(columns: terminalColumns, rows: terminalRows)
        for line in demoLines {
            let color: String
            switch line.kind {
            case .title: color = "1;33"
            case .command: color = "32"
            case .note: color = "90"
            case .accent: color = "36"
            case .plain: color = "0"
            }
            buffer.feed("\u{1B}[\(color)m\(line.text)\u{1B}[0m\r\n")
        }
        return buffer
    }
    private var completionWords: [String] {
        let common = ["look", "inventory", "score", "help", "hp", "who", "quit", "say", "north", "south", "east", "west", "get", "drop", "/walk", "/stop"]
        let recent = session.lines.suffix(100).joined(separator: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 && $0.count < 30 }
        return common + automation.configuration.aliases.filter(\.enabled).map(\.name) + recent.suffix(300) + history
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 224)
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(spacing: 0) {
                workspaceHeader
                Rectangle().fill(Palette.border).frame(height: 1)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        terminalToolbar
                        if showSearch { searchBar }
                        terminal
                        if !world.isDemo, session.isConnected, let step = session.loginStep {
                            loginGuide(step)
                        }
                        commandBar
                    }
                    if showInspector {
                        Rectangle().fill(Palette.border).frame(width: 1)
                        CharacterPanel(isDemo: world.isDemo, canSend: canPlay, character: session.character, gmcpAvailable: session.gmcpAvailable, isConnected: session.isConnected, send: submit)
                            .frame(width: 246)
                    }
                }
                statusBar
            }
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.canvas)
        .preferredColorScheme(.dark)
        .sheet(item: $editingWorld) { item in
            WorldEditor(world: item) { saved in
                if saved.id == selection { session.reset() }
                library.save(saved)
                select(saved)
            }
        }
        .sheet(isPresented: $showAutomation) {
            AutomationEditor(draft: automation.configuration, worldName: world.name) { automation.configuration = $0 }
        }
        .background {
            ShortcutMonitor(rules: automation.configuration.keys,
                            enabled: canSend && !session.isPasswordInput && !showAutomation && editingWorld == nil,
                            action: submit).frame(width: 0, height: 0)
            Group {
                Button("Focus command") { focusRequest += 1 }.keyboardShortcut("k")
                Button("Find in output") { showSearch.toggle() }.keyboardShortcut("f")
                Button("Add world", action: addWorld).keyboardShortcut("n")
            }
            .hidden()
        }
        .onAppear {
            automation.load(world.id)
            session.configure(automation.configuration)
            session.resize(columns: terminalColumns, rows: terminalRows)
        }
        .onChange(of: automation.configuration) { session.configure($0) }
        .onDisappear { session.disconnect(announce: false) }
        .onChange(of: session.isConnected) { connected in
            if connected { DispatchQueue.main.async { focusRequest += 1 } }
        }
        .onChange(of: session.isPasswordInput) { _ in
            command = ""
            showHistory = false
            focusRequest += 1
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Palette.jade.opacity(0.12)).frame(width: 34, height: 34)
                    Image(systemName: "mountain.2").font(.system(size: 17)).foregroundStyle(Palette.jade)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("NewZMud").font(.system(size: 16, weight: .semibold))
                    Text("A world in words").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 35)

            HStack {
                SectionLabel(title: "Your worlds")
                Spacer()
                QuietIconButton(symbol: "plus", label: "Add world", action: addWorld)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            ForEach(library.worlds) { item in
                Button { select(item) } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: item.isDemo ? "mountain.2" : "globe.asia.australia")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(selection == item.id ? Palette.jade : Palette.muted)
                            .frame(width: 22).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name).font(.system(size: 14, weight: .medium))
                            Text(item.subtitle.isEmpty ? item.host : item.subtitle)
                                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if selection == item.id {
                            Circle().fill(Palette.jade).frame(width: 5, height: 5).padding(.top, 7)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 13)
                    .background(selection == item.id ? Palette.jade.opacity(0.08) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.bottom, 4)
                .contextMenu {
                    if !item.isDemo {
                        Button("Edit world") { editingWorld = item }
                            .disabled(item.id == selection && session.canCancelConnection)
                        Button("Remove world", role: .destructive) {
                            if selection == item.id { select(.demo) }
                            library.worlds.removeAll { $0.id == item.id }
                        }
                    }
                }
            }
            Button(action: addWorld) {
                Label("Add a world", systemImage: "plus")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            .buttonStyle(.plain).padding(.horizontal, 10).padding(.top, 6)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "text.quote").font(.system(size: 17)).foregroundStyle(Palette.gold.opacity(0.6))
                Text("江湖路远，\n且行且歌。")
                    .font(.system(size: 16, design: .serif)).lineSpacing(6).foregroundStyle(Palette.muted)
                Text("Every adventure starts with a word.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack {
                Circle().fill(Palette.jade.opacity(0.6)).frame(width: 5, height: 5)
                Text("macOS edition").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Text("0.2").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            }.padding(20)
        }
        .background(Palette.panel)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(world.name).font(.system(size: 20, weight: .medium, design: .serif))
                    if world.isDemo {
                        Text("PREVIEW").font(.system(size: 9, weight: .semibold)).tracking(1)
                            .foregroundStyle(Palette.gold).padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Palette.gold.opacity(0.09)).clipShape(Capsule())
                    }
                }
                Text(world.isDemo ? "An old jianghu. A new beginning." : "\(world.host) : \(world.port)")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if world.isDemo {
                Button { demoLines = DemoWorld.introduction } label: {
                    Label("Restart preview", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
            } else {
                Button(action: connectionAction) {
                    Label(session.reconnectIn != nil ? "Cancel retry" : (session.isConnecting ? "Cancel" : (session.isConnected ? "Disconnect" : "Connect")), systemImage: session.canCancelConnection ? "stop.circle" : "bolt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.jade).padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Palette.jade.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                QuietIconButton(symbol: "slider.horizontal.3", label: "Edit world") { editingWorld = world }
                    .disabled(session.canCancelConnection)
            }
            Rectangle().fill(Palette.border).frame(width: 1, height: 22).padding(.horizontal, 6)
            QuietIconButton(symbol: "sidebar.right", label: "Toggle character panel") {
                withAnimation(.easeInOut(duration: 0.18)) { showInspector.toggle() }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var terminalToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal").font(.system(size: 12)).foregroundStyle(Palette.jade)
            Text("Game").font(.system(size: 12, weight: .medium))
            Spacer()
            if world.isDemo {
                Text("LOCAL PREVIEW · NO SERVER CONNECTION")
                    .font(.system(size: 9, weight: .medium)).tracking(0.8).foregroundStyle(Palette.muted)
            }
            Menu {
                Button("Rules and shortcuts…") { showAutomation = true }
                Toggle("Enable triggers and timers", isOn: Binding(
                    get: { session.automationEnabled }, set: { session.setAutomationEnabled($0) }
                )).disabled(!session.isConnected || session.isPasswordInput)
                Toggle("Reconnect automatically", isOn: $automation.configuration.autoReconnect)
            } label: {
                Label(session.automationEnabled ? "Automation on" : "Automation", systemImage: "bolt")
                    .font(.system(size: 11)).foregroundStyle(session.automationEnabled ? Palette.jade : Palette.muted)
            }.menuStyle(.borderlessButton).fixedSize().help("Per-world rules and shortcuts")
            if session.automationEnabled || session.queuedCommands > 0 {
                Button { session.stopAutomation() } label: {
                    Label("Stop", systemImage: "stop.circle").font(.system(size: 11)).foregroundStyle(Palette.gold)
                }.buttonStyle(.plain).keyboardShortcut(".", modifiers: .command)
            }
            QuietIconButton(symbol: "magnifyingglass", label: "Find in output · ⌘F") { showSearch.toggle() }
            Menu {
                Button("Increase text size") { fontSize = min(fontSize + 1, 22) }
                Button("Decrease text size") { fontSize = max(fontSize - 1, 11) }
                Divider()
                Button("Clear output") {
                    if world.isDemo { demoLines = [] } else { session.clearOutput() }
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Palette.muted).frame(width: 22)
            }
            .menuStyle(.borderlessButton).fixedSize().help("Terminal options")
        }
        .padding(.leading, 24).padding(.trailing, 18).padding(.vertical, 10)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
            TextField("Filter output…", text: $search).textFieldStyle(.plain)
            Text("\(displayBuffer.plainLines.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }.count) lines").font(.caption).foregroundStyle(Palette.muted)
            QuietIconButton(symbol: "xmark", label: "Close search") { search = ""; showSearch = false }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(Palette.raised).clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 24).padding(.bottom, 8)
    }

    private var terminal: some View {
        TerminalView(buffer: displayBuffer, fontSize: fontSize, search: search,
                     following: $followingOutput, newOutput: $pendingOutput) { columns, rows in
            terminalColumns = columns; terminalRows = rows
            if !world.isDemo { session.resize(columns: columns, rows: rows) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if !followingOutput && pendingOutput > 0 {
                Button {
                    followingOutput = true; pendingOutput = 0
                } label: {
                    Label("New output", systemImage: "arrow.down")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.canvas)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Palette.jade).clipShape(Capsule())
                }.buttonStyle(.plain).padding(18)
            }
        }
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("›").font(.system(size: 24, weight: .light, design: .monospaced)).foregroundStyle(Palette.jade)
                CommandInput(text: $command, history: history, completions: completionWords,
                             secret: session.isPasswordInput && !world.isDemo, enabled: canSend,
                             focusRequest: focusRequest, onSubmit: submit)
                    .frame(height: 22)
                Button { submit(command) } label: {
                    Image(systemName: "return").font(.system(size: 13))
                        .foregroundStyle(Palette.jade).frame(width: 32, height: 30)
                        .background(Palette.jade.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain).disabled(!canSend || (world.isDemo && command.isEmpty)).help("Send command")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.jade.opacity(canSend ? 0.28 : 0.12)))
            HStack(spacing: 14) {
                Text("↑↓ history · Tab complete · ⌘K focus").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Rectangle().fill(Palette.border).frame(width: 1, height: 10)
                ForEach(["look", "inventory", "score"], id: \.self) { text in
                    Button(text) { submit(text) }
                        .buttonStyle(.plain).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.muted).disabled(!canPlay)
                }
                Spacer()
                Button { showHistory.toggle() } label: {
                    Label("History", systemImage: "clock.arrow.circlepath").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.muted)
                .disabled(session.isPasswordInput)
                .popover(isPresented: $showHistory) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Recent commands")
                        if history.isEmpty { Text("Your commands will appear here.").foregroundStyle(Palette.muted).font(.caption) }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(history.reversed().enumerated()), id: \.offset) { _, item in
                                    Button { command = item; showHistory = false; focusRequest += 1 } label: {
                                        Text(item).font(.system(size: 12, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(7).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.frame(maxHeight: 220)
                    }.padding(18).frame(width: 280).background(Palette.panel)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 18)
    }

    private func loginGuide(_ step: LoginStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.isPasswordInput ? "lock.fill" : "person.text.rectangle")
                .font(.system(size: 14)).foregroundStyle(session.isPasswordInput ? Palette.gold : Palette.jade)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("LOGIN GUIDE").font(.system(size: 9, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(Palette.muted)
                    Text(step.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                }
                Text(step.guidance).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if session.isPasswordInput {
                Text("NOT SAVED").font(.system(size: 9, weight: .medium)).tracking(0.5)
                    .foregroundStyle(Palette.gold).padding(.top, 2)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
        .padding(.horizontal, 24).padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Login guide. \(step.title). \(step.guidance)")
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle().fill(world.isDemo ? Palette.gold : (session.isConnected ? Palette.jade : Palette.muted)).frame(width: 5, height: 5)
            Text(world.isDemo ? "Preview mode" : session.status)
            Spacer()
            if session.queuedCommands > 0 { Text("\(session.queuedCommands) queued"); Text("·") }
            Text(world.isDemo ? "Sample character & room data" : (session.gmcpAvailable ? "GMCP connected" : "Telnet"))
            Text("·").padding(.horizontal, 5)
            Text(world.isDemo ? "UTF-8 preview" : "UTF-8")
        }
        .font(.system(size: 10)).foregroundStyle(Palette.muted)
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(Palette.panel)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private var canSend: Bool { world.isDemo || session.isConnected }
    private var canPlay: Bool {
        canSend && !session.isPasswordInput && (world.isDemo || !session.gmcpAvailable || session.character.updated != nil)
    }

    private func addWorld() {
        editingWorld = World(name: "", subtitle: "", host: "", port: "4000")
    }

    private func select(_ item: World) {
        guard selection != item.id else { return }
        session.reset()
        selectionID = item.id.uuidString
        automation.load(item.id)
        session.configure(automation.configuration)
        session.resize(columns: terminalColumns, rows: terminalRows)
        followingOutput = true; pendingOutput = 0
        command = ""
        search = ""
        history = []
    }

    private func connectionAction() {
        if session.canCancelConnection {
            session.disconnect()
        } else if let port = UInt16(world.port) {
            followingOutput = true; pendingOutput = 0
            session.connect(host: world.host, port: port)
            focusRequest += 1
        }
    }

    private func submit(_ text: String) {
        guard canSend, !world.isDemo || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !session.isPasswordInput && !text.isEmpty {
            history.append(text)
            if history.count > 100 { history.removeFirst() }
        }
        if world.isDemo {
            do {
                var commands = try CommandExpansion.aliases(text, rules: automation.configuration.aliases)
                if text.hasPrefix("/walk ") { commands = try CommandExpansion.walk(String(text.dropFirst(6))) }
                for item in commands {
                    demoLines += [.init(text: ""), .init(text: "› \(item)", kind: .command)] + DemoWorld.response(to: item)
                }
            } catch { demoLines.append(.init(text: error.localizedDescription, kind: .note)) }
            if demoLines.count > 1000 { demoLines.removeFirst(demoLines.count - 1000) }
        } else {
            session.send(text)
        }
        command = ""
        focusRequest += 1
    }
}
