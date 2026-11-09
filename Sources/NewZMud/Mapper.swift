import SwiftUI

enum RoomMarker: String, Codable, CaseIterable, Identifiable {
    case none, landmark, shop, quest, danger, safe
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .none: ""
        case .landmark: "mappin.and.ellipse"
        case .shop: "cart"
        case .quest: "flag"
        case .danger: "exclamationmark.triangle"
        case .safe: "checkmark.shield"
        }
    }
}

struct MappedRoom: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var area: String?
    var roomID: String?
    var exits: [String]
    var x: Int
    var y: Int
    var note: String? = nil
    var marker: RoomMarker? = nil
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
    private var pendingDirections: [String] = []

    func load(worldID: UUID) {
        guard selectedWorldID != worldID else { return }
        selectedWorldID = worldID
        previousRoomID = nil
        pendingDirections = []
        let data = UserDefaults.standard.data(forKey: storageKey(worldID))
        map = data.flatMap { try? JSONDecoder().decode(WorldMap.self, from: $0) } ?? WorldMap()
    }

    func noteCommand(_ command: String, exits: Set<String>, rules: [ExitCommandRule]) {
        let value = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return }
        for exit in exits {
            let mapped = rules.first { $0.exit.caseInsensitiveCompare(exit) == .orderedSame }?.command
            if value == exit.lowercased() || mapped?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == value {
                pendingDirections.append(canonicalDirection(exit))
                return
            }
        }
        pendingDirections.removeAll()
    }

    func noteRoute(_ directions: [String]) {
        pendingDirections.append(contentsOf: directions.map(canonicalDirection))
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
            let position = newPosition(from: previousRoomID, direction: pendingDirections.first)
            map.rooms.append(MappedRoom(id: roomID, name: name, area: character.area,
                                        roomID: character.roomID, exits: character.exits.sorted(),
                                        x: position.x, y: position.y))
        }
        let changedRoom = previousRoomID != nil && previousRoomID != roomID
        if changedRoom, let previousRoomID, let direction = pendingDirections.first {
            addConnection(from: previousRoomID, to: roomID, direction: direction)
            pendingDirections.removeFirst()
        }
        previousRoomID = roomID
        map.currentRoomID = roomID
        persist()
    }

    func moveRoom(_ id: String, by delta: (x: Int, y: Int)) {
        guard let index = map.rooms.firstIndex(where: { $0.id == id }) else { return }
        let x = map.rooms[index].x + delta.x
        let y = map.rooms[index].y + delta.y
        guard !map.rooms.contains(where: { $0.id != id && $0.x == x && $0.y == y }) else { return }
        map.rooms[index].x = x
        map.rooms[index].y = y
        persist()
    }

    func updateDetails(_ id: String, note: String, marker: RoomMarker) {
        guard let index = map.rooms.firstIndex(where: { $0.id == id }) else { return }
        map.rooms[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        map.rooms[index].marker = marker == .none ? nil : marker
        persist()
    }

    func route(to destination: String) -> [MappedConnection]? {
        guard let origin = map.currentRoomID, origin != destination else { return nil }
        var queue: [(room: String, path: [MappedConnection])] = [(origin, [])]
        var visited: Set<String> = [origin]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            for edge in map.connections where edge.from == next.room {
                if edge.to == destination { return next.path + [edge] }
                if visited.insert(edge.to).inserted { queue.append((edge.to, next.path + [edge])) }
            }
        }
        return nil
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
        let target = (x: room.x + delta.0, y: room.y + delta.1)
        let blocked: (Int, Int) -> Bool = { x, y in self.map.rooms.contains(where: { $0.x == x && $0.y == y }) }
        guard blocked(target.x, target.y) else { return target }
        let candidates = (-8...8).flatMap { y in (-8...8).map { x in (x: target.x + x, y: target.y + y) } }
            .filter { !blocked($0.x, $0.y) }
            .sorted { lhs, rhs in
                let leftDistance = abs(lhs.x - target.x) + abs(lhs.y - target.y)
                let rightDistance = abs(rhs.x - target.x) + abs(rhs.y - target.y)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                let leftProjection = (lhs.x - target.x) * delta.0 + (lhs.y - target.y) * delta.1
                let rightProjection = (rhs.x - target.x) * delta.0 + (rhs.y - target.y) * delta.1
                if leftProjection != rightProjection { return leftProjection > rightProjection }
                return lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
            }
        return candidates.first.map { ($0.x, $0.y) } ?? target
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
    @Binding var zoom: Double
    var move: (MappedRoom) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRoomID: String?

    private let cellWidth: CGFloat = 230
    private let cellHeight: CGFloat = 170
    private let roomCardWidth: CGFloat = 206
    private let roomCardHeight: CGFloat = 104

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
                    Text("\(store.map.roomCount) rooms · drag rooms to arrange · scroll to pan")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { setZoom(zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.borderless).disabled(zoom <= 0.5)
                Text("\(Int(zoom * 100))%").font(.system(size: 10, design: .monospaced)).frame(width: 38)
                Button { setZoom(zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.borderless).disabled(zoom >= 1.8)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(18)
            Rectangle().fill(Palette.border).frame(height: 1)
            if let selected = selectedRoom {
                selectedRoomDetail(selected)
                Rectangle().fill(Palette.border).frame(height: 1)
            }
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
                    mapCanvas
                        .scaleEffect(zoom, anchor: .topLeading)
                        .frame(width: max(cellWidth, CGFloat(bounds.maxX - bounds.minX + 1) * cellWidth) * zoom,
                               height: max(cellHeight, CGFloat(bounds.maxY - bounds.minY + 1) * cellHeight) * zoom,
                               alignment: .topLeading)
                        .padding(44 * zoom)
                }
                .background(Palette.canvas)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.dark)
    }

    private var selectedRoom: MappedRoom? {
        let id = selectedRoomID ?? store.map.currentRoomID
        return store.map.rooms.first { $0.id == id }
    }

    private func setZoom(_ value: Double) { zoom = min(1.8, max(0.5, value)) }

    private func selectedRoomDetail(_ room: MappedRoom) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(room.name).font(.system(size: 13, weight: .semibold))
                    if room.id == store.map.currentRoomID {
                        Text("CURRENT").font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(Palette.jade)
                    }
                }
                Text("Area: \(room.area ?? "Unknown")  ·  Room ID: \(room.roomID ?? "Unavailable")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1)
                TextField("Add a room note…", text: Binding(
                    get: { room.note ?? "" },
                    set: { store.updateDetails(room.id, note: $0, marker: room.marker ?? .none) }
                ))
                .textFieldStyle(.roundedBorder).font(.system(size: 10)).frame(maxWidth: 350)
            }
            Spacer()
            Picker("Marker", selection: Binding(
                get: { room.marker ?? .none },
                set: { store.updateDetails(room.id, note: room.note ?? "", marker: $0) }
            )) {
                ForEach(RoomMarker.allCases) { marker in
                    Text(marker.title).tag(marker)
                }
            }
            .frame(width: 120)
            if let route = store.route(to: room.id), !route.isEmpty {
                Button { move(room) } label: {
                    Label("Move here · \(route.count)", systemImage: "figure.walk")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderedProminent).tint(Palette.jade).foregroundStyle(Palette.canvas)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Palette.panel)
    }

    private var mapCanvas: some View {
        let width = CGFloat(bounds.maxX - bounds.minX + 1) * cellWidth
        let height = CGFloat(bounds.maxY - bounds.minY + 1) * cellHeight
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for link in store.map.connections {
                    guard let from = store.map.rooms.first(where: { $0.id == link.from }),
                          let to = store.map.rooms.first(where: { $0.id == link.to }) else { continue }
                    let fromCenter = point(for: from)
                    let toCenter = point(for: to)
                    let dx = toCenter.x - fromCenter.x
                    let dy = toCenter.y - fromCenter.y
                    let length = max(1, hypot(dx, dy))
                    let ux = dx / length
                    let uy = dy / length
                    let startInset = min((roomCardWidth / 2) / max(abs(ux), 0.001), (roomCardHeight / 2) / max(abs(uy), 0.001))
                    let endInset = min((roomCardWidth / 2) / max(abs(ux), 0.001), (roomCardHeight / 2) / max(abs(uy), 0.001))
                    let start = CGPoint(x: fromCenter.x + ux * startInset, y: fromCenter.y + uy * startInset)
                    let end = CGPoint(x: toCenter.x - ux * endInset, y: toCenter.y - uy * endInset)
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    context.stroke(path, with: .color(Palette.jade.opacity(0.45)), lineWidth: 2)
                }
            }
            ForEach(store.map.rooms) { room in
                roomCard(room)
                    .position(point(for: room))
                    .simultaneousGesture(DragGesture(minimumDistance: 5)
                        .onEnded { value in
                            let dx = Int((value.translation.width / zoom / cellWidth).rounded())
                            let dy = Int((value.translation.height / zoom / cellHeight).rounded())
                            if dx != 0 || dy != 0 { store.moveRoom(room.id, by: (dx, dy)) }
                        })
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
        let selected = room.id == selectedRoomID || (selectedRoomID == nil && current)
        let canMove = store.route(to: room.id)?.isEmpty == false
        return HStack(spacing: 4) {
            Button { selectedRoomID = room.id } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        if current { Image(systemName: "location.fill").foregroundStyle(Palette.jade) }
                        Text(room.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }
                    if let marker = room.marker {
                        Label(marker.title, systemImage: marker.symbol)
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(markerColor(marker))
                    }
                    if let area = room.area {
                        Text(area).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    if let note = room.note, !note.isEmpty {
                        Text(note).font(.system(size: 8)).foregroundStyle(Palette.ink.opacity(0.8)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if canMove {
                Button { move(room) } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.jade)
                }
                .buttonStyle(.plain).help("Move to \(room.name)")
            }
        }
        .padding(9).frame(width: roomCardWidth, height: roomCardHeight, alignment: .leading)
        .background(current ? Palette.jade.opacity(0.13) : Palette.raised,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Palette.jade.opacity(0.8) : Palette.border, lineWidth: 1))
    }

    private func markerColor(_ marker: RoomMarker) -> Color {
        switch marker {
        case .danger: Palette.gold
        case .safe: Palette.jade
        default: Palette.muted
        }
    }
}
