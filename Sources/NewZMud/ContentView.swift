import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var library = WorldLibrary()
    @StateObject private var worldSessions = WorldSessions()
    @StateObject private var automation = AutomationStore()
    @StateObject private var mapper = MapperStore()
    @StateObject private var navigationWindow = NavigationWindowController()
    @AppStorage("selectedWorldID") private var selectionID = World.demo.id.uuidString
    @State private var editingWorld: World?
    @State private var showInspector = true
    @State private var command = ""
    @State private var history: [String] = []
    @State private var showHistory = false
    @State private var search = ""
    @State private var showSearch = false
    @State private var showGMCPDiagnostics = false
    @State private var showMapper = false
    @State private var mapZoom = 1.0
    @State private var demoLines = DemoWorld.introduction
    @State private var focusRequest = 0
    @State private var showAutomation = false
    @State private var followingOutput = true
    @State private var pendingOutput = 0
    @State private var terminalColumns = 80
    @State private var terminalRows = 30
    @State private var bookmarks: [TerminalBookmark] = []
    @State private var exportError: String?

    private var selection: UUID { UUID(uuidString: selectionID) ?? World.demo.id }
    private var world: World { library.worlds.first { $0.id == selection } ?? .demo }
    private var session: MUDSession { worldSessions.session(for: selection) }
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
        let actionCommands = automation.configuration.quickActions.filter(\.enabled).flatMap { action in
            CommandExpansion.actions(action.command).flatMap { command in
                [command, String(command.split(whereSeparator: \.isWhitespace).first ?? "")]
            }
        }
        let exitMappings = automation.configuration.exitCommands
        let exits = (world.isDemo ? ["north", "east", "south", "west"] : Array(session.character.exits)).flatMap { exit in
            [exit, exitMappings.first { $0.exit.caseInsensitiveCompare(exit) == .orderedSame }?.command ?? exit]
        }
        let aliases = automation.configuration.aliases.filter(\.enabled).map(\.name)
        return ["/walk", "/stop"] + actionCommands + exits + aliases + history
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
                        if !world.isDemo, !session.isConnected, !session.isConnecting,
                           (session.canReconnect || session.reconnectIn != nil) {
                            reconnectBanner
                        }
                        commandBar
                    }
                    if showInspector && (world.isDemo || (session.isConnected && session.character.hasCharacterInfo)) {
                        Rectangle().fill(Palette.border).frame(width: 1)
                        CharacterPanel(isDemo: world.isDemo, canSend: canPlay,
                                       character: session.character, gmcpAvailable: session.gmcpAvailable,
                                       isConnected: session.isConnected,
                                       quickActions: automation.configuration.quickActions,
                                       vitalLabels: automation.configuration.vitalLabels,
                                       hideEmptyVitals: automation.configuration.hideEmptyVitals,
                                       vitalOrder: automation.configuration.vitalOrder,
                                       hiddenVitals: automation.configuration.hiddenVitals,
                                       send: submit)
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
            WorldEditor(world: item, encoding: automation.configuration(for: item.id).terminalEncoding) { saved, encoding, connect in
                worldSessions.reset(saved.id)
                automation.setTerminalEncoding(encoding, for: saved.id)
                library.save(saved)
                select(saved)
                if connect {
                    automation.load(saved.id)
                    session.configure(automation.configuration)
                    connectionAction()
                }
            }
        }
        .sheet(isPresented: $showAutomation) {
            AutomationEditor(draft: automation.configuration, worldName: world.name,
                             currentVitals: session.character.vitals) { automation.configuration = $0 }
        }
        .sheet(isPresented: $showGMCPDiagnostics) {
            GMCPDiagnosticsView(session: session, automation: automation)
        }
        .sheet(isPresented: $showMapper) {
            MapperView(store: mapper, zoom: $mapZoom, move: moveToMappedRoom)
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
            loadBookmarks(for: world.id)
            mapper.load(worldID: world.id)
            mapper.receive(session.character)
            worldSessions.activate(world.id)
            session.configure(automation.configuration)
            session.resize(columns: terminalColumns, rows: terminalRows)
            syncNavigationWindow()
        }
        .onReceive(session.$character) { character in
            mapper.receive(character)
            syncNavigationWindow()
        }
        .onChange(of: selectionID) { _ in
            mapper.load(worldID: selection)
            loadBookmarks(for: selection)
            syncNavigationWindow()
        }
        .onChange(of: automation.configuration) { configuration in
            session.configure(configuration)
            syncNavigationWindow()
        }
        .onDisappear { worldSessions.disconnectAll() }
        .onChange(of: session.isConnected) { connected in
            if connected { DispatchQueue.main.async { focusRequest += 1 } }
            syncNavigationWindow()
        }
        .onChange(of: session.isPasswordInput) { _ in
            command = ""
            showHistory = false
            focusRequest += 1
            syncNavigationWindow()
        }
        .alert("Couldn’t export transcript", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
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
                            worldSessions.remove(item.id)
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
                    Label(connectionButtonTitle, systemImage: connectionButtonIcon)
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
            Button { showMapper = true } label: {
                Label("Map", systemImage: "map")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain).help("Open discovered world map")
            if world.isDemo || (session.isConnected && session.character.hasRoom) {
                Button { openNavigationWindow() } label: {
                    Label("Navigation", systemImage: "location.north.line")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain).help("Open navigation window")
            }
            Menu {
                Button("Bookmark latest output line", systemImage: "bookmark") { addBookmark() }
                    .disabled(latestBookmarkLine == nil)
                if !bookmarks.isEmpty {
                    Divider()
                    ForEach(bookmarks) { bookmark in
                        Button(bookmark.line) {
                            search = bookmark.line
                            showSearch = true
                            followingOutput = true
                            pendingOutput = 0
                        }
                    }
                    Button("Remove all bookmarks", role: .destructive) { saveBookmarks([]) }
                }
            } label: {
                Image(systemName: "bookmark").foregroundStyle(Palette.muted).frame(width: 22)
            }
            .menuStyle(.borderlessButton).fixedSize().help("Bookmark terminal output")
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
                Button("Increase text size") { automation.configuration.terminalFontSize = min(automation.configuration.terminalFontSize + 1, 22) }
                Button("Decrease text size") { automation.configuration.terminalFontSize = max(automation.configuration.terminalFontSize - 1, 11) }
                Divider()
                Button("Export transcript…", systemImage: "square.and.arrow.up") { exportTranscript() }
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
        TerminalView(buffer: displayBuffer, fontSize: automation.configuration.terminalFontSize,
                     theme: automation.configuration.terminalTheme, search: search,
                     following: $followingOutput, newOutput: $pendingOutput) { columns, rows in
            terminalColumns = columns; terminalRows = rows
            if !world.isDemo { session.resize(columns: columns, rows: rows) }
        } onNavigate: { direction in
            navigate(direction)
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
                             secret: session.isPasswordInput && !world.isDemo,
                             enabled: canSend,
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(automation.configuration.quickActions.filter(\.enabled)) { action in
                            Button(action.title) { submit(action.command) }
                                .buttonStyle(.plain).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.muted).disabled(!canPlay)
                        }
                    }
                }
                .frame(maxWidth: 300, alignment: .leading)
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

    private var reconnectBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 15)).foregroundStyle(Palette.gold).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("Connection interrupted")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(session.reconnectIn.map { "Retrying in \($0)s. Your game may ask you to sign in again." } ?? session.status)
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Reconnect now") { session.reconnectNow(); focusRequest += 1 }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.canvas)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Palette.jade).clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.gold.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.gold.opacity(0.2)))
        .padding(.horizontal, 24).padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle().fill(statusIndicatorColor).frame(width: 5, height: 5)
            Text(connectionStatusText)
            Spacer()
            if session.queuedCommands > 0 { Text("\(session.queuedCommands) queued"); Text("·") }
            Button { showGMCPDiagnostics = true } label: {
                HStack(spacing: 4) {
                    Text(world.isDemo ? "Sample data" : (session.gmcpAvailable ? "GMCP" : "Telnet"))
                    Image(systemName: "waveform.path.ecg").font(.system(size: 9))
                }
            }
            .buttonStyle(.plain).help("Open GMCP diagnostics")
            Text("·").padding(.horizontal, 5)
            Text(world.isDemo ? "UTF-8 preview" : automation.configuration.terminalEncoding.title)
        }
        .font(.system(size: 10)).foregroundStyle(Palette.muted)
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(Palette.panel)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private var connectionStatusText: String {
        if world.isDemo { return "Preview mode" }
        guard session.isConnected else { return session.status }
        if session.isPasswordInput { return "Login · password required" }
        if session.character.hasCharacterInfo { return "Game data ready" }
        if let loginStatus = session.loginStatus { return loginStatus }
        if session.gmcpAvailable { return "GMCP connected · waiting for login" }
        return "Telnet connected · configure login prompts for sign-in status"
    }

    private var statusIndicatorColor: Color {
        if world.isDemo { return Palette.gold }
        guard session.isConnected else { return Palette.muted }
        return session.character.hasCharacterInfo ? Palette.jade : Palette.gold
    }

    private var canSend: Bool { world.isDemo || session.isConnected }
    private var connectionButtonTitle: String {
        if session.reconnectIn != nil { return "Cancel retry" }
        if session.isConnecting { return "Cancel" }
        if session.isConnected { return "Disconnect" }
        return session.canReconnect ? "Reconnect" : "Connect"
    }
    private var connectionButtonIcon: String {
        session.canCancelConnection ? "stop.circle" : (session.canReconnect ? "arrow.clockwise" : "bolt")
    }
    private var canPlay: Bool {
        canSend && !session.isPasswordInput && (world.isDemo || !session.gmcpAvailable || session.character.updated != nil)
    }

    private func addWorld() {
        editingWorld = World(name: "", subtitle: "", host: "", port: "4000")
    }

    private func syncNavigationWindow() {
        navigationWindow.update(worldName: world.name, isDemo: world.isDemo, canSend: canPlay,
                                character: session.character,
                                exitCommands: automation.configuration.exitCommands,
                                send: { command in submit(command) })
    }

    private func openNavigationWindow() {
        syncNavigationWindow()
        navigationWindow.show()
    }

    private var latestBookmarkLine: String? {
        displayBuffer.plainLines.reversed().first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func addBookmark() {
        guard let line = latestBookmarkLine else { return }
        if bookmarks.contains(where: { $0.line == line }) { return }
        saveBookmarks([TerminalBookmark(line: line)] + bookmarks.prefix(99))
    }

    private func loadBookmarks(for id: UUID) {
        let data = UserDefaults.standard.data(forKey: "terminalBookmarks.\(id.uuidString)")
        bookmarks = data.flatMap { try? JSONDecoder().decode([TerminalBookmark].self, from: $0) } ?? []
    }

    private func saveBookmarks(_ values: [TerminalBookmark]) {
        bookmarks = values
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: "terminalBookmarks.\(world.id.uuidString)")
    }

    private func exportTranscript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(world.name)-transcript.txt"
        let transcript = displayBuffer.plainText
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(transcript.utf8).write(to: url, options: .atomic)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func select(_ item: World) {
        guard selection != item.id else { return }
        selectionID = item.id.uuidString
        worldSessions.activate(item.id)
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
        } else if session.canReconnect {
            session.reconnectNow()
        } else if let port = UInt16(world.port) {
            followingOutput = true; pendingOutput = 0
            session.connect(host: world.host, port: port)
            focusRequest += 1
        }
    }

    private func submit(_ text: String) {
        submit(text, focusInput: true)
    }

    private func moveToMappedRoom(_ room: MappedRoom) {
        guard canPlay, !world.isDemo, let route = mapper.route(to: room.id), !route.isEmpty else { return }
        let commands = route.compactMap { edge -> (direction: String, command: String)? in
            guard let source = mapper.map.rooms.first(where: { $0.id == edge.from }),
                  let exit = source.exits.first(where: { canonicalDirection($0) == edge.direction }) else { return nil }
            let command = automation.configuration.exitCommands.first {
                $0.exit.caseInsensitiveCompare(exit) == .orderedSame
            }?.command ?? exit
            return (edge.direction, command)
        }
        guard commands.count == route.count else { return }
        mapper.noteRoute(commands.map(\.direction))
        for item in commands {
            history.append(item.command)
            session.send(item.command)
        }
        if history.count > 100 { history.removeFirst(history.count - 100) }
    }

    private func canonicalDirection(_ exit: String) -> String {
        switch exit.lowercased() {
        case "n", "north": "north"
        case "ne", "northeast", "north-east": "northeast"
        case "e", "east": "east"
        case "se", "southeast", "south-east": "southeast"
        case "s", "south": "south"
        case "sw", "southwest", "south-west": "southwest"
        case "w", "west": "west"
        case "nw", "northwest", "north-west": "northwest"
        default: exit.lowercased()
        }
    }

    private func navigate(_ direction: String) -> Bool {
        guard canPlay else { return false }
        if world.isDemo {
            submit(direction, focusInput: false)
            return true
        }
        let aliases: [String: Set<String>] = [
            "north": ["north", "n"], "east": ["east", "e"],
            "south": ["south", "s"], "west": ["west", "w"],
            "northwest": ["northwest", "north-west", "nw"],
            "northeast": ["northeast", "north-east", "ne"],
            "southwest": ["southwest", "south-west", "sw"],
            "southeast": ["southeast", "south-east", "se"]
        ]
        guard let accepted = aliases[direction],
              let reportedExit = session.character.exits.first(where: { accepted.contains($0.lowercased()) }) else { return false }
        let command = automation.configuration.exitCommands.first {
            $0.exit.caseInsensitiveCompare(reportedExit) == .orderedSame
        }?.command ?? reportedExit
        submit(command, focusInput: false)
        return true
    }

    private func submit(_ text: String, focusInput: Bool) {
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
            mapper.noteCommand(text, exits: session.character.exits, rules: automation.configuration.exitCommands)
            session.send(text)
        }
        command = ""
        if focusInput { focusRequest += 1 }
    }
}
