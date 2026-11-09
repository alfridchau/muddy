import AppKit
import SwiftUI

@MainActor
final class NavigationWindowModel: ObservableObject {
    @Published var worldName = "World"
    @Published var isDemo = false
    @Published var canSend = false
    @Published var character = CharacterState()
    @Published var exitCommands: [ExitCommandRule] = []
    var send: (String) -> Void = { _ in }
}

@MainActor
final class NavigationWindowController: ObservableObject {
    let model = NavigationWindowModel()
    private var windowController: NSWindowController?

    func update(worldName: String, isDemo: Bool, canSend: Bool,
                character: CharacterState, exitCommands: [ExitCommandRule], send: @escaping (String) -> Void) {
        model.worldName = worldName
        model.isDemo = isDemo
        model.canSend = canSend
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
            window.setFrameAutosaveName("NewZMud.NavigationWindow")
            window.contentViewController = NSHostingController(rootView: NavigationSubwindowView(model: model))
            windowController = NSWindowController(window: window)
            window.center()
        }
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct NavigationSubwindowView: View {
    @ObservedObject var model: NavigationWindowModel

    var body: some View {
        NavigationOverlay(isDemo: model.isDemo, canSend: model.canSend,
                          character: model.character, exitCommands: model.exitCommands,
                          send: model.send, move: model.send)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.canvas)
            .foregroundStyle(Palette.ink)
            .preferredColorScheme(.dark)
    }
}
