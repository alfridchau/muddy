import AppKit
import SwiftUI

struct CommandInput: NSViewRepresentable {
    @Binding var text: String
    var history: [String]
    var completions: [String]
    var secret: Bool
    var enabled: Bool
    var focusRequest: Int
    var onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> InputHost {
        let host = InputHost()
        host.normal.delegate = context.coordinator
        host.secure.delegate = context.coordinator
        context.coordinator.host = host
        return host
    }
    func updateNSView(_ host: InputHost, context: Context) {
        let coordinator = context.coordinator
        let changedMode = coordinator.parent.secret != secret
        coordinator.parent = self
        host.normal.isHidden = secret
        host.secure.isHidden = !secret
        let field = secret ? host.secure : host.normal
        host.normal.isEnabled = enabled
        host.secure.isEnabled = enabled
        field.placeholderString = secret ? "Password…" : "Enter a command…"
        field.setAccessibilityLabel(secret ? "Password input" : "Command input")
        if field.stringValue != text { field.stringValue = text; coordinator.recall.reset(); coordinator.completion.reset() }
        if changedMode { coordinator.recall.reset(); coordinator.completion.reset() }
        if coordinator.lastFocus != focusRequest || changedMode {
            coordinator.lastFocus = focusRequest
            DispatchQueue.main.async { [weak host] in
                guard let host, enabled else { return }
                host.window?.makeFirstResponder(field)
                field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandInput
        weak var host: InputHost?
        var recall = CommandRecall()
        var completion = CommandCompletion()
        var lastFocus = -1
        init(_ parent: CommandInput) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            recall.reset(); completion.reset()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }
            switch NSStringFromSelector(selector) {
            case "insertNewline:":
                parent.onSubmit(field.stringValue)
                recall.reset(); completion.reset()
                return true
            case "moveUp:", "moveDown:":
                guard !parent.secret else { return true }
                replace(recall.move(up: NSStringFromSelector(selector) == "moveUp:", current: field.stringValue, history: parent.history), field: field)
                completion.reset()
                return true
            case "insertTab:", "insertBacktab:":
                guard !parent.secret else { return true }
                replace(completion.complete(field.stringValue, words: parent.completions, backwards: NSStringFromSelector(selector) == "insertBacktab:"), field: field)
                return true
            default: return false
            }
        }

        private func replace(_ value: String, field: NSTextField) {
            field.stringValue = value
            parent.text = value
            field.currentEditor()?.string = value
            field.currentEditor()?.selectedRange = NSRange(location: (value as NSString).length, length: 0)
        }
    }
}

final class InputHost: NSView {
    let normal = NSTextField()
    let secure = NSSecureTextField()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [normal, secure] {
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            field.textColor = NSColor(Palette.ink)
            field.autoresizingMask = [.width, .height]
            addSubview(field)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); normal.frame = bounds; secure.frame = bounds }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }
}

struct ShortcutMonitor: NSViewRepresentable {
    var rules: [KeyRule]
    var enabled: Bool
    var action: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        context.coordinator.host = host
        context.coordinator.install()
        return host
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.parent = self }
    final class Coordinator {
        var parent: ShortcutMonitor
        weak var host: NSView?
        var monitor: Any?
        init(_ parent: ShortcutMonitor) { self.parent = parent }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.parent.enabled, !event.isARepeat, event.window === self.host?.window else { return event }
                let codes: [UInt16: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
                let key = codes[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
                let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                for rule in self.parent.rules where rule.enabled && rule.isValid && rule.key.uppercased() == key {
                    var expected: NSEvent.ModifierFlags = []
                    if rule.command { expected.insert(.command) }
                    if rule.control { expected.insert(.control) }
                    if rule.option { expected.insert(.option) }
                    if rule.shift { expected.insert(.shift) }
                    if expected == flags { self.parent.action(rule.commands); return nil }
                }
                return event
            }
        }
    }
}
