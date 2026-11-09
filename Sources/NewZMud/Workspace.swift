import SwiftUI

enum Palette {
    static let canvas = Color(red: 0.055, green: 0.067, blue: 0.078)
    static let panel = Color(red: 0.080, green: 0.094, blue: 0.106)
    static let raised = Color(red: 0.106, green: 0.125, blue: 0.137)
    static let border = Color.white.opacity(0.075)
    static let ink = Color(red: 0.81, green: 0.84, blue: 0.84)
    static let muted = Color(red: 0.49, green: 0.55, blue: 0.57)
    static let jade = Color(red: 0.51, green: 0.79, blue: 0.66)
    static let gold = Color(red: 0.82, green: 0.69, blue: 0.45)
}

struct World: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var subtitle: String
    var host: String
    var port: String
    var isDemo = false

    static let demo = World(
        id: UUID(uuidString: "151DE8FC-9B3E-4EE0-8DAA-9F8CA0B6FF00")!,
        name: "笑傲江湖", subtitle: "XO MUD · Wuxia", host: "", port: "4000", isDemo: true
    )
}

@MainActor
final class WorldLibrary: ObservableObject {
    @Published var worlds: [World] { didSet { persist() } }
    @Published private(set) var favoriteIDs: Set<UUID>
    @Published private(set) var recentIDs: [UUID]

    init() {
        let data = UserDefaults.standard.data(forKey: "savedWorlds")
        let saved = data.flatMap { try? JSONDecoder().decode([World].self, from: $0) } ?? []
        worlds = [.demo] + saved.filter { !$0.isDemo }
        favoriteIDs = Set((UserDefaults.standard.data(forKey: "favoriteWorldIDs")
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) }) ?? [])
        recentIDs = (UserDefaults.standard.data(forKey: "recentWorldIDs")
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) }) ?? []
        recentIDs = recentIDs.filter { id in worlds.contains(where: { $0.id == id && !$0.isDemo }) }
    }

    func save(_ world: World) {
        if let index = worlds.firstIndex(where: { $0.id == world.id }) {
            worlds[index] = world
        } else {
            worlds.append(world)
        }
    }

    func isFavorite(_ id: UUID) -> Bool { favoriteIDs.contains(id) }

    func toggleFavorite(_ id: UUID) {
        guard worlds.contains(where: { $0.id == id && !$0.isDemo }) else { return }
        if !favoriteIDs.insert(id).inserted { favoriteIDs.remove(id) }
        persistProfileLists()
    }

    func markRecent(_ id: UUID) {
        guard worlds.contains(where: { $0.id == id && !$0.isDemo }) else { return }
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        recentIDs = Array(recentIDs.prefix(5))
        persistProfileLists()
    }

    func remove(_ id: UUID) {
        worlds.removeAll { $0.id == id }
        favoriteIDs.remove(id)
        recentIDs.removeAll { $0 == id }
        persistProfileLists()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(worlds.filter { !$0.isDemo }) {
            UserDefaults.standard.set(data, forKey: "savedWorlds")
        }
    }

    private func persistProfileLists() {
        if let data = try? JSONEncoder().encode(Array(favoriteIDs)) {
            UserDefaults.standard.set(data, forKey: "favoriteWorldIDs")
        }
        if let data = try? JSONEncoder().encode(recentIDs) {
            UserDefaults.standard.set(data, forKey: "recentWorldIDs")
        }
    }
}

struct TerminalLine: Identifiable {
    var id = UUID()
    var text: String
    var kind: Kind = .plain

    enum Kind {
        case plain, title, note, command, accent

        var color: Color {
            switch self {
            case .plain: return Palette.ink
            case .title: return Palette.gold
            case .note: return Palette.muted
            case .command: return Palette.jade
            case .accent: return Color(red: 0.65, green: 0.73, blue: 0.86)
            }
        }
    }
}

struct TerminalBookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var line: String
    var createdAt = Date()
}

enum DemoWorld {
    static let introduction: [TerminalLine] = [
        .init(text: "欢迎来到笑傲江湖", kind: .title),
        .init(text: "山河故人，江湖再见。", kind: .note),
        .init(text: ""),
        .init(text: "这是一段可交互的界面预览，并未连接游戏服务器。", kind: .note),
        .init(text: "Try look, north, inventory, or score to explore the preview.", kind: .note),
        .init(text: ""),
    ] + room("扬州广场")

    static func room(_ name: String) -> [TerminalLine] {
        [
            .init(text: "\(name) — Yangzhou", kind: .title),
            .init(text: ""),
            .init(text: "    青石板铺就的广场上人来人往。几株老槐树投下斑驳的树影，"),
            .init(text: "    茶香随着微风飘过街头，远处传来小贩悠长的吆喝声。"),
            .init(text: "    一位白发老者坐在树下，悠然地望着往来的江湖行客。"),
            .init(text: ""),
            .init(text: "    这里明显的出口是 north、south、east 和 west。", kind: .accent),
            .init(text: "    布衣老者 (Old man)", kind: .accent),
            .init(text: ""),
            .init(text: "气血 820/1000 · 内力 360/500 · 精神 240/300", kind: .note),
        ]
    }

    static func response(to command: String) -> [TerminalLine] {
        let words = command.lowercased().trimmingCharacters(in: .whitespaces)
        switch words {
        case "l", "look": return room("扬州广场")
        case "n", "north", "s", "south", "e", "east", "w", "west", "ne", "nw", "se", "sw":
            return [.init(text: "你沿着青石小路向前走去。", kind: .note)] + room("扬州街巷")
        case "i", "inventory":
            return [.init(text: "你随身携带着：", kind: .title), .init(text: "    一柄青钢剑    一件布衣    一只水袋"), .init(text: "    二两白银      三块干粮")]
        case "score", "hp":
            return [.init(text: "江湖新客 · 无门无派", kind: .title), .init(text: "    气血 820 / 1000    内力 360 / 500"), .init(text: "    精神 240 / 300     经验 12,450")]
        case "help":
            return [.init(text: "Preview commands", kind: .title), .init(text: "    look · north · south · east · west · inventory · score"), .init(text: "Add a world in the sidebar to configure a real connection.", kind: .note)]
        default:
            return [.init(text: "Preview: “\(command)” entered. Try help for available commands.", kind: .note)]
        }
    }
}

struct QuietIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Palette.muted)
    }
}
