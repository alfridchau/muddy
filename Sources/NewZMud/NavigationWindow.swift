import AppKit
import SwiftUI

@MainActor
final class NavigationWindowModel: ObservableObject {
    @Published var worldName = "World"
    @Published var isDemo = false
    @Published var canSend = false
    @Published var connectionStatus = "Disconnected"
    @Published var character = CharacterState()
    @Published var exitCommands: [ExitCommandRule] = []
    var send: (String) -> Void = { _ in }
}

@MainActor
final class NavigationWindowController: NSObject, ObservableObject, NSWindowDelegate {
    let model = NavigationWindowModel()
    @Published private(set) var isOpen = false
    var onVisibilityChanged: ((Bool) -> Void)?
    private var windowController: NSWindowController?
    private var isTerminating = false
    private var terminationObserver: NSObjectProtocol?

    override init() {
        super.init()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isTerminating = true }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func update(worldName: String, isDemo: Bool, canSend: Bool, connectionStatus: String,
                character: CharacterState, exitCommands: [ExitCommandRule], send: @escaping (String) -> Void) {
        model.worldName = worldName
        model.isDemo = isDemo
        model.canSend = canSend
        model.connectionStatus = connectionStatus
        model.character = character
        model.exitCommands = exitCommands
        model.send = send
        windowController?.window?.title = "Navigation · \(worldName)"
    }

    func show() {
        if windowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Navigation · \(model.worldName)"
            window.minSize = NSSize(width: 260, height: 380)
            window.isReleasedWhenClosed = false
            window.delegate = self
            if !window.setFrameAutosaveName("NewZMud.NavigationWindow") { window.center() }
            window.contentViewController = NSHostingController(rootView: NavigationSubwindowView(model: model))
            windowController = NSWindowController(window: window)
        }
        windowController?.showWindow(nil)
        isOpen = true
        onVisibilityChanged?(true)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
        if !isTerminating { onVisibilityChanged?(false) }
    }
}

private struct NavigationSubwindowView: View {
    @ObservedObject var model: NavigationWindowModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: model.isDemo ? "mountain.2" : "globe.asia.australia")
                    .font(.system(size: 14)).foregroundStyle(Palette.jade)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.worldName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(statusColor).frame(width: 5, height: 5)
                        Text(model.connectionStatus).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollView(.vertical) {
                NavigationOverlay(isDemo: model.isDemo, canSend: model.canSend,
                                  character: model.character, exitCommands: model.exitCommands,
                                  send: model.send, move: model.send)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(Palette.canvas)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.dark)
    }

    private var statusColor: Color {
        if model.isDemo { return Palette.jade }
        let status = model.connectionStatus.lowercased()
        if ["failed", "closed", "timed out", "error", "exhausted", "interrupted"].contains(where: status.contains) {
            return Color(red: 0.90, green: 0.43, blue: 0.39)
        }
        if model.canSend { return Palette.jade }
        if ["connecting", "waiting", "reconnecting"].contains(where: status.contains) { return Palette.gold }
        return Palette.muted
    }
}
