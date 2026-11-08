import SwiftUI

struct MappedRoom: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var area: String?
    var roomID: String?
    var exits: [String]
    var x: Int
    var y: Int
}

struct MappedConnection: Codable, Equatable, Identifiable {
    var from: String
    var to: String
    var direction: String
    var id: String { "\(from)|\(direction)|\(to)" }
}

struct WorldMap: Codable, Equatable {
    var rooms: [MappedRoom] = []
    var connections: [MappedConnection] = []
    var currentRoomID: String?
    var roomCount: Int { rooms.count }
}

@MainActor
final class MapperStore: ObservableObject {
    @Published private(set) var map = WorldMap()
    @Published private(set) var selectedWorldID: UUID?
    private var previousRoomID: String?
    private var pendingDirection: String?

    func load(worldID: UUID) {
        guard selectedWorldID != worldID else { return }
        selectedWorldID = worldID
        previousRoomID = nil
        pendingDirection = nil
        let data = UserDefaults.standard.data(forKey: storageKey(worldID))
        map = data.flatMap { try? JSONDecoder().decode(WorldMap.self, from: $0) } ?? WorldMap()
    }

    func noteCommand(_ command: String, exits: Set<String>, rules: [ExitCommandRule]) {
        let value = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return }
        for exit in exits {
            let mapped = rules.first { $0.exit.caseInsensitiveCompare(exit) == .orderedSame }?.command
            if value == exit.lowercased() || mapped?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == value {
                pendingDirection = canonicalDirection(exit)
                return
            }
        }
        pendingDirection = nil
    }

    func receive(_ character: CharacterState) {
        guard character.hasRoom, let name = character.room, !name.isEmpty else { return }
        let roomID = Self.key(roomID: character.roomID, area: character.area, name: name)
        if let index = map.rooms.firstIndex(where: { $0.id == roomID }) {
            map.rooms[index].name = name
            map.rooms[index].area = character.area
            map.rooms[index].roomID = character.roomID
            map.rooms[index].exits = character.exits.sorted()
        } else {
            let position = newPosition(from: previousRoomID, direction: pendingDirection)
            map.rooms.append(MappedRoom(id: roomID, name: name, area: character.area,
                                        roomID: character.roomID, exits: character.exits.sorted(),
                                        x: position.x, y: position.y))
        }
        let changedRoom = previousRoomID != nil && previousRoomID != roomID
        if changedRoom, let previousRoomID, let direction = pendingDirection {
            addConnection(from: previousRoomID, to: roomID, direction: direction)
        }
        previousRoomID = roomID
        if changedRoom { pendingDirection = nil }
        map.currentRoomID = roomID
        persist()
    }

    func clear() {
        map = WorldMap()
        previousRoomID = nil
        pendingDirection = nil
        persist()
    }

    private func newPosition(from previous: String?, direction: String?) -> (x: Int, y: Int) {
        guard let previous, let room = map.rooms.first(where: { $0.id == previous }) else { return (0, 0) }
        let delta: (Int, Int)
        switch direction {
        case "north": delta = (0, -1)
        case "northeast": delta = (1, -1)
        case "east": delta = (1, 0)
        case "southeast": delta = (1, 1)
        case "south": delta = (0, 1)
        case "southwest": delta = (-1, 1)
        case "west": delta = (-1, 0)
        case "northwest": delta = (-1, -1)
        default: delta = (1, 0)
        }
        var candidate = (x: room.x + delta.0, y: room.y + delta.1)
        while map.rooms.contains(where: { $0.x == candidate.x && $0.y == candidate.y }) {
            candidate.x += 1
        }
        return candidate
    }

    private func addConnection(from: String, to: String, direction: String) {
        guard map.rooms.contains(where: { $0.id == from }), map.rooms.contains(where: { $0.id == to }) else { return }
        if !map.connections.contains(where: { $0.from == from && $0.to == to && $0.direction == direction }) {
            map.connections.append(MappedConnection(from: from, to: to, direction: direction))
        }
    }

    private func persist() {
        guard let selectedWorldID, let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(selectedWorldID))
    }

    private func storageKey(_ id: UUID) -> String { "worldMap.\(id.uuidString)" }

    private static func key(roomID: String?, area: String?, name: String) -> String {
        if let roomID, !roomID.isEmpty { return "id:\(roomID)" }
        return "name:\((area ?? "").lowercased())|\(name.lowercased())"
    }

    private func canonicalDirection(_ value: String) -> String {
        switch value.lowercased() {
        case "n", "north": "north"
        case "ne", "northeast", "north-east": "northeast"
        case "e", "east": "east"
        case "se", "southeast", "south-east": "southeast"
        case "s", "south": "south"
        case "sw", "southwest", "south-west": "southwest"
        case "w", "west": "west"
        case "nw", "northwest", "north-west": "northwest"
        default: value.lowercased()
        }
    }
}

struct MapperView: View {
    @ObservedObject var store: MapperStore
    @Environment(\.dismiss) private var dismiss

    private let cellWidth: CGFloat = 150
    private let cellHeight: CGFloat = 104

    private var bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        guard !store.map.rooms.isEmpty else { return (0, 0, 0, 0) }
        return (store.map.rooms.map(\.x).min() ?? 0, store.map.rooms.map(\.x).max() ?? 0,
                store.map.rooms.map(\.y).min() ?? 0, store.map.rooms.map(\.y).max() ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("World map").font(.system(size: 18, weight: .semibold))
                    Text("\(store.map.roomCount) rooms discovered · map fills in as you explore")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if store.map.roomCount > 0 {
                    Button("Clear map…", systemImage: "trash") { store.clear() }
                        .buttonStyle(.borderless).foregroundStyle(Palette.muted)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(18)
            Rectangle().fill(Palette.border).frame(height: 1)
            if store.map.rooms.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "map").font(.system(size: 28)).foregroundStyle(Palette.muted)
                    Text("No rooms mapped yet").font(.system(size: 15, weight: .semibold))
                    Text("Connect to a MUD with room data, then explore. New rooms and exits will appear here.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    mapCanvas.padding(44)
                }
                .background(Palette.canvas)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.dark)
    }

    private var mapCanvas: some View {
        let width = CGFloat(bounds.maxX - bounds.minX + 1) * cellWidth
        let height = CGFloat(bounds.maxY - bounds.minY + 1) * cellHeight
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for link in store.map.connections {
                    guard let from = store.map.rooms.first(where: { $0.id == link.from }),
                          let to = store.map.rooms.first(where: { $0.id == link.to }) else { continue }
                    let start = point(for: from)
                    let end = point(for: to)
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    context.stroke(path, with: .color(Palette.jade.opacity(0.45)), lineWidth: 2)
                    let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    context.draw(Text(link.direction.uppercased()).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Palette.muted), at: midpoint)
                }
            }
            ForEach(store.map.rooms) { room in
                roomCard(room)
                    .position(point(for: room))
            }
        }
        .frame(width: max(cellWidth, width), height: max(cellHeight, height))
    }

    private func point(for room: MappedRoom) -> CGPoint {
        CGPoint(x: CGFloat(room.x - bounds.minX) * cellWidth + cellWidth / 2,
                y: CGFloat(room.y - bounds.minY) * cellHeight + cellHeight / 2)
    }

    private func roomCard(_ room: MappedRoom) -> some View {
        let current = room.id == store.map.currentRoomID
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if current { Image(systemName: "location.fill").foregroundStyle(Palette.jade) }
                Text(room.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            if let area = room.area {
                Text(area).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Text(room.exits.isEmpty ? "Exits unknown" : "Exits: \(room.exits.sorted().joined(separator: ", "))")
                .font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(2)
        }
        .padding(9).frame(width: cellWidth - 18, height: 72, alignment: .leading)
        .background(current ? Palette.jade.opacity(0.13) : Palette.raised,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(current ? Palette.jade.opacity(0.65) : Palette.border, lineWidth: 1))
    }
}
