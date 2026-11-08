import SwiftUI
import AppKit

struct CharacterPanel: View {
    var isDemo: Bool
    var canSend: Bool
    var character: CharacterState
    var gmcpAvailable: Bool
    var isConnected: Bool
    var quickActions: [QuickAction]
    var vitalLabels: [VitalLabelRule]
    var hideEmptyVitals: Bool
    var vitalOrder: [String]
    var hiddenVitals: Set<String>
    var send: (String) -> Void

    private var displayedVitals: [CharacterVital] {
        let vitals: [CharacterVital]
        if isDemo {
            vitals = [
                CharacterVital(id: "hp", name: "Health", current: 820, maximum: 1_000),
                CharacterVital(id: "mp", name: "Mana", current: 240, maximum: 300),
                CharacterVital(id: "moves", name: "Movement", current: 180, maximum: 300),
                CharacterVital(id: "energy", name: "Energy", current: 360, maximum: 500)
            ]
        } else {
            vitals = character.vitals
        }
        let labels = Dictionary(vitalLabels.map { ($0.field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.label) }, uniquingKeysWith: { _, latest in latest })
        let order = Dictionary(vitalOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return vitals.enumerated()
            .filter { !(hideEmptyVitals && $0.element.current == 0 && $0.element.maximum == 0) }
            .filter { !hiddenVitals.contains($0.element.id) }
            .map { indexedVital in
                var labeledVital = indexedVital.element
                if !isDemo, let label = labels[labeledVital.id.lowercased()], !label.isEmpty { labeledVital.name = label }
                return (indexedVital.offset, labeledVital)
            }
            .sorted { lhs, rhs in
                let left = order[lhs.1.id] ?? Int.max
                let right = order[rhs.1.id] ?? Int.max
                return left == right ? lhs.0 < rhs.0 : left < right
            }
            .map(\.1)
    }

    private let vitalColors: [Color] = [
        Palette.jade,
        Palette.gold,
        Color(red: 0.76, green: 0.61, blue: 0.84),
        Color(red: 0.52, green: 0.66, blue: 0.85),
        Color(red: 0.82, green: 0.60, blue: 0.46)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    SectionLabel(title: "Character")
                    Spacer()
                    if isDemo {
                        Text("SAMPLE").font(.system(size: 8, weight: .semibold)).tracking(1)
                            .foregroundStyle(Palette.muted)
                    }
                }
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Palette.gold.opacity(0.08)).frame(width: 44, height: 48)
                        Image(systemName: "person.fill").font(.system(size: 20, weight: .light))
                            .foregroundStyle(Palette.gold)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(isDemo ? "江湖新客" : (character.name ?? "Your character")).font(.system(size: 15, weight: .medium))
                        Text(isDemo ? "无门无派 · Wanderer" : (character.title ?? (character.updated == nil ? "Awaiting game data" : (isConnected ? "Live character data" : "Last known values"))))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
                VStack(spacing: 18) {
                    ForEach(Array(displayedVitals.enumerated()), id: \.offset) { index, vital in
                        stat(vital, color: vitalColors[index % vitalColors.count])
                    }
                }
                if isDemo || character.experience != nil {
                    HStack {
                        Text("Experience").foregroundStyle(Palette.muted)
                        Spacer()
                        Text(isDemo ? "12,450" : (character.experience?.formatted() ?? "—")).monospacedDigit()
                    }.font(.system(size: 11))
                }
                if isDemo || character.potential != nil {
                    HStack {
                        Text("Potential").foregroundStyle(Palette.muted)
                        Spacer()
                        Text(isDemo ? "8,240" : (character.potential?.formatted() ?? "—")).monospacedDigit()
                    }.font(.system(size: 11))
                }
                Rectangle().fill(Palette.border).frame(height: 1)
                if !quickActions.filter(\.enabled).isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionLabel(title: "At your fingertips")
                        ForEach(quickActions.filter(\.enabled)) { action in
                            shortcut(action.title, command: action.command, symbol: action.symbol)
                        }
                    }
                }
                if isDemo {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkle").foregroundStyle(Palette.gold)
                        Text("A little glimpse of the jianghu. Add your own world when you're ready to connect.")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                    .padding(12).background(Palette.gold.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(gmcpAvailable ? "Stats update every three seconds after the game provides character data." : "This server has not enabled GMCP. You can still use score and hp in the terminal.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 24)
        }
        .background(Palette.panel.opacity(0.6))
    }

    private func stat(_ vital: CharacterVital, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(vital.name).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Text(vital.text).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.raised)
                    Capsule().fill(color.opacity(0.8)).frame(width: geometry.size.width * vital.fraction)
                }
            }.frame(height: 4)
        }
    }

    private func shortcut(_ title: String, command: String, symbol: String) -> some View {
        Button { send(command) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Palette.muted).frame(width: 15)
                Text(title).font(.system(size: 11))
                Spacer()
                Text(command).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!canSend)
    }
}

struct NavigationOverlay: View {
    @State private var isExpanded = false
    @State private var roomIDCopied = false
    var isDemo: Bool
    var canSend: Bool
    var character: CharacterState
    var exitCommands: [ExitCommandRule]
    var send: (String) -> Void

    private var exitsSummary: String {
        let exits = character.exits.sorted().joined(separator: ", ")
        return exits.isEmpty ? "none reported" : exits
    }

    private var displayedExits: [(name: String, command: String)] {
        let mappings = Dictionary(exitCommands.map { ($0.exit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.command) }, uniquingKeysWith: { _, latest in latest })
        let names = isDemo ? ["nw", "north", "ne", "west", "east", "sw", "south", "se"] : character.exits.sorted()
        return names.map { name in (name, mappings[name.lowercased()] ?? name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "location.north.fill").font(.system(size: 10)).foregroundStyle(Palette.jade)
                    Text("Navigation").font(.system(size: 11, weight: .semibold))
                    if !isExpanded, let room = character.room {
                        Text("· \(room)").font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if isDemo { Text("SAMPLE").font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.muted) }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse navigation" : "Expand navigation")
            if isExpanded {
                if !isDemo && (character.room != nil || character.area != nil || character.roomID != nil || character.hasRoom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let room = character.room {
                            Text(room).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.gold).lineLimit(1)
                        }
                        if let area = character.area { Text("Area · \(area)").font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1) }
                        if let roomID = character.roomID {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(roomID, forType: .string)
                                roomIDCopied = true
                            } label: {
                                Label(roomIDCopied ? "Room ID copied" : "Copy room ID", systemImage: roomIDCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted)
                            }
                            .buttonStyle(.plain).help("Copy room ID")
                        }
                        if character.hasRoom {
                            Text("Exits · \(exitsSummary)").font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(2)
                        }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(Array(displayedExits.enumerated()), id: \.offset) { _, exit in
                        exitButton(exit.name, command: exit.command)
                    }
                }
                Button { send("look") } label: {
                    Label("Look", systemImage: "location.circle")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.jade)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(Palette.jade.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain).disabled(!canSend).help("Look around")
            }
        }
        .padding(12)
        .frame(width: isExpanded ? 172 : nil)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.border.opacity(0.9), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }

    private func exitButton(_ exit: String, command: String) -> some View {
        Button { send(command) } label: {
            Text(exit.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.65)
                .foregroundStyle(Palette.jade)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Palette.raised.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).disabled(!canSend).help("Exit: \(exit) · command: \(command)")
    }
}
