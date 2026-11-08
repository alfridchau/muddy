import SwiftUI

struct CharacterPanel: View {
    var isDemo: Bool
    var canSend: Bool
    var character: CharacterState
    var gmcpAvailable: Bool
    var isConnected: Bool
    var send: (String) -> Void

    private var displayedVitals: [CharacterVital] {
        if isDemo {
            return [
                CharacterVital(id: "hp", name: "Health", current: 820, maximum: 1_000),
                CharacterVital(id: "mp", name: "Mana", current: 240, maximum: 300),
                CharacterVital(id: "moves", name: "Movement", current: 180, maximum: 300),
                CharacterVital(id: "energy", name: "Energy", current: 360, maximum: 500)
            ]
        }
        return character.vitals
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
                Rectangle().fill(Palette.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionLabel(title: "Navigation")
                        Spacer()
                        Image(systemName: "location.north").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    if !isDemo, let room = character.room {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(room).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.gold)
                            if let area = character.area { Text(area).font(.caption).foregroundStyle(Palette.muted) }
                        }
                    }
                    VStack(spacing: 5) {
                        HStack(spacing: 5) {
                            direction("NW", command: "nw")
                            direction("N", command: "north")
                            direction("NE", command: "ne")
                        }
                        HStack(spacing: 5) {
                            direction("W", command: "west")
                            Button { send("look") } label: {
                                Image(systemName: "location.circle")
                                    .font(.system(size: 20, weight: .light)).foregroundStyle(Palette.jade)
                                    .frame(width: 51, height: 42)
                                    .background(Palette.jade.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain).disabled(!canSend).help("Look around")
                            direction("E", command: "east")
                        }
                        HStack(spacing: 5) {
                            direction("SW", command: "sw")
                            direction("S", command: "south")
                            direction("SE", command: "se")
                        }
                    }.frame(maxWidth: .infinity)
                    Text(!isDemo && character.hasRoom ? "Available exits are highlighted." : "Click a direction to walk.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                }
                Rectangle().fill(Palette.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 13) {
                    SectionLabel(title: "At your fingertips")
                    shortcut("Look around", command: "look", symbol: "eye")
                    shortcut("Inventory", command: "inventory", symbol: "bag")
                    shortcut("Character sheet", command: "score", symbol: "person.text.rectangle")
                    shortcut("Help", command: "help", symbol: "questionmark.circle")
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

    private func direction(_ label: String, command: String) -> some View {
        let available = isDemo || !character.hasRoom || character.exits.contains(command) || character.exits.contains(label.lowercased())
        return Button { send(command) } label: {
            Text(label).font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(available && !isDemo && character.hasRoom ? Palette.jade : Palette.muted).frame(width: 51, height: 42)
                .background(Palette.raised.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).disabled(!canSend || !available).help("Walk \(command)")
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
