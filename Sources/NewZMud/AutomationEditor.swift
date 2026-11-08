import SwiftUI

struct AutomationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: WorldConfiguration
    var worldName: String
    var currentVitals: [CharacterVital] = []
    var onSave: (WorldConfiguration) -> Void
    @State private var section = "Actions"
    private let sections = ["Actions", "Stats", "Exits", "Login", "Display", "Aliases", "Triggers", "Timers", "Keys", "Walking"]

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
        let actions = draft.quickActions.filter(\.enabled)
        if actions.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Enabled quick actions need a label and command."
        }
        let labels = draft.vitalLabels.filter { !$0.field.isEmpty || !$0.label.isEmpty }
        if labels.contains(where: { $0.field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Stat labels need both a GMCP field and a display label."
        }
        if Set(labels.map { $0.field.lowercased() }).count != labels.count { return "Stat label fields must be unique." }
        let exitRules = draft.exitCommands.filter { !$0.exit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if exitRules.contains(where: { $0.exit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Exit mappings need both an exit name and a command."
        }
        if Set(exitRules.map { $0.exit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count != exitRules.count {
            return "Exit mapping names must be unique."
        }
        if draft.loginPrompts.contains(where: { $0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (try? NSRegularExpression(pattern: $0.pattern, options: .caseInsensitive)) == nil }) {
            return "Login prompts need valid regular expressions."
        }
        if !(11...22).contains(draft.terminalFontSize) { return "Terminal text size must be between 11 and 22 points." }
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sections, id: \.self) { item in
                        Button(item) { section = item }
                            .font(.system(size: 10, weight: section == item ? .semibold : .regular))
                            .foregroundStyle(section == item ? Palette.ink : Palette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(section == item ? Palette.jade.opacity(0.16) : Palette.raised)
                            .clipShape(Capsule()).buttonStyle(.plain)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch section {
                    case "Actions": quickActions
                    case "Stats": stats
                    case "Exits": exits
                    case "Login": login
                    case "Display": display
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
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            hint("Create buttons for commands used by this world. These actions are saved separately for each world.")
            ForEach($draft.quickActions) { $action in
                VStack(alignment: .leading, spacing: 10) {
                    ruleHeader(enabled: $action.enabled, remove: { draft.quickActions.removeAll { $0.id == action.id } })
                    HStack(spacing: 8) {
                        TextField("Button label", text: $action.title).textFieldStyle(.roundedBorder)
                        TextField("SF Symbol", text: $action.symbol).textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                    TextField("Command", text: $action.command).textFieldStyle(.roundedBorder)
                }.padding(12).background(Palette.raised).cornerRadius(8)
            }
            Button("Add quick action", systemImage: "plus") {
                draft.quickActions.append(QuickAction(title: "New action", command: "", symbol: "bolt"))
            }
        }
    }
    private var stats: some View {
        VStack(alignment: .leading, spacing: 14) {
            hint("Give this world's GMCP stat fields friendly labels. For example, map a field named hp to Health or jingli to Stamina.")
            Toggle("Hide empty 0 / 0 stats", isOn: $draft.hideEmptyVitals).toggleStyle(.checkbox)
            if currentVitals.isEmpty {
                hint("Connect to this world first to load its stat fields. You can still add label mappings below.")
            } else {
                Text("Panel order and visibility").font(.system(size: 12, weight: .medium))
                ForEach(Array(orderedVitals.enumerated()), id: \.element.id) { index, vital in
                    HStack(spacing: 7) {
                        Button { moveVital(vital.id, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0).buttonStyle(.plain).foregroundStyle(Palette.muted)
                        Button { moveVital(vital.id, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == orderedVitals.count - 1).buttonStyle(.plain).foregroundStyle(Palette.muted)
                        Text(vitalLabel(for: vital)).lineLimit(1)
                        Text(vital.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1)
                        Spacer()
                        Toggle("Show", isOn: Binding(
                            get: { !draft.hiddenVitals.contains(vital.id) },
                            set: { visible in
                                if visible { draft.hiddenVitals.remove(vital.id) }
                                else { draft.hiddenVitals.insert(vital.id) }
                            }
                        )).labelsHidden().toggleStyle(.checkbox)
                    }.font(.system(size: 11)).padding(8).background(Palette.raised).cornerRadius(7)
                }
            }
            ForEach($draft.vitalLabels) { $rule in
                HStack(spacing: 8) {
                    TextField("GMCP field", text: $rule.field).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(Palette.muted)
                    TextField("Display label", text: $rule.label).textFieldStyle(.roundedBorder)
                    QuietIconButton(symbol: "trash", label: "Remove stat label") {
                        draft.vitalLabels.removeAll { $0.id == rule.id }
                    }
                }.padding(10).background(Palette.raised).cornerRadius(8)
            }
            Button("Add stat label", systemImage: "plus") { draft.vitalLabels.append(VitalLabelRule()) }
        }
    }
    private var exits: some View {
        VStack(alignment: .leading, spacing: 14) {
            hint("Room exits become buttons automatically. Add a mapping when the exit name shown by the MUD differs from the command to send. Unmapped exits use their reported name as the command.")
            ForEach($draft.exitCommands) { $rule in
                HStack(spacing: 8) {
                    TextField("Reported exit, e.g. north", text: $rule.exit).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(Palette.muted)
                    TextField("Command to send, e.g. n", text: $rule.command).textFieldStyle(.roundedBorder)
                    QuietIconButton(symbol: "trash", label: "Remove exit mapping") {
                        draft.exitCommands.removeAll { $0.id == rule.id }
                    }
                }.padding(10).background(Palette.raised).cornerRadius(8)
            }
            Button("Add exit mapping", systemImage: "plus") { draft.exitCommands.append(ExitCommandRule()) }
        }
    }
    private var login: some View {
        VStack(alignment: .leading, spacing: 14) {
            hint("Match incoming terminal lines to show the current login step. Password matches mask input and send it without adding it to command history. Prompts are never answered automatically.")
            ForEach($draft.loginPrompts) { $rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("When this prompt matches", selection: $rule.kind) {
                            ForEach(LoginPromptKind.allCases) { kind in Text(kind.title).tag(kind) }
                        }.labelsHidden().frame(width: 180)
                        Spacer()
                        QuietIconButton(symbol: "trash", label: "Remove login prompt") {
                            draft.loginPrompts.removeAll { $0.id == rule.id }
                        }
                    }
                    TextField("Regular expression for a complete prompt line", text: $rule.pattern).textFieldStyle(.roundedBorder)
                }.padding(10).background(Palette.raised).cornerRadius(8)
            }
            Button("Add login prompt", systemImage: "plus") { draft.loginPrompts.append(LoginPromptRule()) }
        }
    }
    private var display: some View {
        VStack(alignment: .leading, spacing: 18) {
            hint("These display and text encoding settings apply only to this world.")
            HStack {
                Text("Text size")
                Slider(value: $draft.terminalFontSize, in: 11...22, step: 1)
                Text("\(Int(draft.terminalFontSize)) pt").monospacedDigit().frame(width: 42, alignment: .trailing)
            }
            Picker("Text encoding", selection: $draft.terminalEncoding) {
                ForEach(MUDTextEncoding.allCases) { Text($0.title).tag($0) }
            }
            Picker("Terminal colors", selection: $draft.terminalTheme) {
                ForEach(TerminalTheme.allCases) { Text($0.title).tag($0) }
            }
            hint("If text appears corrupted, choose the encoding used by the MUD. Reconnect after changing encoding so the server and client start with a clean text stream.")
        }
    }

    private var orderedVitals: [CharacterVital] {
        let order = Dictionary(draft.vitalOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return currentVitals.enumerated().sorted { lhs, rhs in
            let left = order[lhs.element.id] ?? Int.max
            let right = order[rhs.element.id] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private func vitalLabel(for vital: CharacterVital) -> String {
        draft.vitalLabels.first { $0.field.caseInsensitiveCompare(vital.id) == .orderedSame }?.label ?? vital.name
    }

    private func moveVital(_ id: String, by offset: Int) {
        var order = orderedVitals.map(\.id)
        guard let index = order.firstIndex(of: id) else { return }
        let destination = index + offset
        guard order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        draft.vitalOrder = order
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
