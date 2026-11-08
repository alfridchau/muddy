import SwiftUI

struct AutomationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: WorldConfiguration
    var worldName: String
    var onSave: (WorldConfiguration) -> Void
    @State private var section = "Aliases"
    private let sections = ["Aliases", "Triggers", "Timers", "Keys", "Walking"]

    private var error: String? {
        let aliases = draft.aliases.filter(\.enabled)
        if aliases.contains(where: { $0.name.isEmpty || $0.name.contains(where: \.isWhitespace) || $0.commands.isEmpty }) {
            return "Enabled aliases need a single-word name and commands."
        }
        if Set(aliases.map(\.name)).count != aliases.count { return "Alias names must be unique." }
        if draft.triggers.contains(where: { $0.enabled && ($0.pattern.isEmpty || $0.commands.isEmpty || (try? NSRegularExpression(pattern: $0.pattern)) == nil) }) {
            return "Enabled triggers need a valid regular expression and commands."
        }
        if draft.timers.contains(where: { $0.enabled && (!$0.interval.isFinite || $0.interval < 0.5 || $0.interval > 86_400 || $0.commands.isEmpty) }) {
            return "Enabled timers need commands and an interval between 0.5 and 86,400 seconds."
        }
        let keys = draft.keys.filter(\.enabled)
        if keys.contains(where: { !$0.isValid || $0.commands.isEmpty }) { return "Use F1–F12 or a single key with Command, Option, or Control, and enter commands." }
        if Set(keys.map(\.label)).count != keys.count { return "Enabled key bindings must be unique." }
        if !draft.walkDelay.isFinite || draft.walkDelay < 0.1 || draft.walkDelay > 10 { return "Walking delay must be between 0.1 and 10 seconds." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make it your world").font(.system(size: 22, weight: .semibold))
                    Text(worldName).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(Palette.jade)
            }
            Picker("Category", selection: $section) {
                ForEach(sections, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch section {
                    case "Aliases": aliases
                    case "Triggers": triggers
                    case "Timers": timers
                    case "Keys": keys
                    default: walking
                    }
                }.padding(.vertical, 6)
            }.frame(height: 335)
            Divider()
            Toggle("Reconnect automatically after an unexpected disconnect", isOn: $draft.autoReconnect)
                .font(.system(size: 12))
            Text("Triggers and timers run only after you enable Automation in a connected session. They pause on disconnect or password prompts. /stop cancels queued commands.")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft); dismiss() }
                    .buttonStyle(.borderedProminent).tint(Palette.jade).keyboardShortcut(.defaultAction).disabled(error != nil)
            }
        }
        .padding(26).frame(width: 610)
        .foregroundStyle(Palette.ink).background(Palette.panel).preferredColorScheme(.dark)
    }

    private var aliases: some View {
        VStack(alignment: .leading, spacing: 14) {
            hint("A short name can run several commands. Use $1…$9 for arguments and $* for all arguments. Example: alias 'greet' → 'say Hello $*'.")
            ForEach($draft.aliases) { $rule in
                VStack(alignment: .leading, spacing: 10) {
                    ruleHeader(enabled: $rule.enabled, remove: { draft.aliases.removeAll { $0.id == rule.id } })
                    TextField("Alias name, e.g. supplies", text: $rule.name).textFieldStyle(.roundedBorder)
                    commands($rule.commands)
                }.padding(12).background(Palette.raised).cornerRadius(8)
            }
            Button("Add alias", systemImage: "plus") { draft.aliases.append(AliasRule()) }
        }
    }
    private var triggers: some View {
        VStack(alignment: .leading, spacing: 14) {
            hint("Match a complete incoming line with a regular expression. Captures become $1…$9; $0 is the full match. Each trigger has a one-second cooldown.")
            ForEach($draft.triggers) { $rule in
                VStack(alignment: .leading, spacing: 10) {
                    ruleHeader(enabled: $rule.enabled, remove: { draft.triggers.removeAll { $0.id == rule.id } })
                    TextField("Pattern, e.g. ^你感到饥饿", text: $rule.pattern).textFieldStyle(.roundedBorder)
                    commands($rule.commands)
                }.padding(12).background(Palette.raised).cornerRadius(8)
            }
            Button("Add trigger", systemImage: "plus") { draft.triggers.append(TriggerRule()) }
        }
    }
    private var timers: some View {
        VStack(alignment: .leading, spacing: 14) {
            hint("Timers repeat at the interval you set. They begin when you enable Automation; reconnecting never restarts them automatically.")
            ForEach($draft.timers) { $rule in
                VStack(alignment: .leading, spacing: 10) {
                    ruleHeader(enabled: $rule.enabled, remove: { draft.timers.removeAll { $0.id == rule.id } })
                    HStack {
                        TextField("Timer name", text: $rule.name).textFieldStyle(.roundedBorder)
                        TextField("Seconds", value: $rule.interval, format: .number).textFieldStyle(.roundedBorder).frame(width: 75)
                        Text("seconds").font(.caption).foregroundStyle(Palette.muted)
                    }
                    commands($rule.commands)
                }.padding(12).background(Palette.raised).cornerRadius(8)
            }
            Button("Add timer", systemImage: "plus") { draft.timers.append(TimerRule()) }
        }
    }
    private var keys: some View {
        VStack(alignment: .leading, spacing: 14) {
            hint("Use F1–F12, or combine one letter with Command, Option, or Control. Bindings apply to this world and pause during password input.")
            ForEach($draft.keys) { $rule in
                VStack(alignment: .leading, spacing: 10) {
                    ruleHeader(enabled: $rule.enabled, remove: { draft.keys.removeAll { $0.id == rule.id } })
                    HStack {
                        TextField("F1 or letter", text: $rule.key).textFieldStyle(.roundedBorder).frame(width: 90)
                        Toggle("⌘", isOn: $rule.command)
                        Toggle("⌥", isOn: $rule.option)
                        Toggle("⌃", isOn: $rule.control)
                        Toggle("⇧", isOn: $rule.shift)
                    }.toggleStyle(.checkbox)
                    commands($rule.commands)
                }.padding(12).background(Palette.raised).cornerRadius(8)
            }
            Button("Add key binding", systemImage: "plus") { draft.keys.append(KeyRule()) }
        }
    }
    private var walking: some View {
        VStack(alignment: .leading, spacing: 20) {
            hint("Enter /walk 2n3e to send two north commands followed by three east commands. Paths support n, s, e, w, ne, nw, se, sw, u, and d, with up to 100 steps.")
            HStack {
                Text("Delay between steps")
                Spacer()
                TextField("Seconds", value: $draft.walkDelay, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
                Text("seconds").foregroundStyle(Palette.muted)
            }
            Text("Use /stop or the Stop button to cancel a walk. Walking is paced by time; movement can fail or be blocked by the game.")
                .font(.caption).foregroundStyle(Palette.muted).lineSpacing(4)
        }
    }
    private func commands(_ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Commands · one per line, or separated by semicolons").font(.caption).foregroundStyle(Palette.muted)
            TextEditor(text: text).font(.system(size: 12, design: .monospaced)).frame(height: 62).padding(4)
                .background(Palette.canvas).cornerRadius(5)
        }
    }
    private func ruleHeader(enabled: Binding<Bool>, remove: @escaping () -> Void) -> some View {
        HStack {
            Toggle("Enabled", isOn: enabled).toggleStyle(.checkbox).font(.caption)
            Spacer()
            QuietIconButton(symbol: "trash", label: "Remove rule", action: remove)
        }
    }
    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
    }
}
