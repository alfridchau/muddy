import Foundation

struct GMCPMessage {
    var module: String
    var json: String

    init?(_ text: String) {
        let parts = text.split(separator: " ", maxSplits: 1)
        guard let name = parts.first, !name.isEmpty else { return nil }
        module = String(name)
        json = parts.count > 1 ? String(parts[1]) : "{}"
    }

    var object: [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

struct CharacterVital: Identifiable, Equatable {
    var id: String
    var name: String
    var current: Int?
    var maximum: Int?
    var fraction: Double {
        guard let current, let maximum, maximum > 0 else { return 0 }
        return min(1, max(0, Double(current) / Double(maximum)))
    }
    var text: String {
        guard let current else { return "—" }
        return maximum.map { "\(current.formatted()) / \($0.formatted())" } ?? current.formatted()
    }
}

struct CharacterState {
    var name: String?
    var title: String?
    var vitals: [CharacterVital] = []
    var experience: Int?
    var potential: Int?
    var room: String?
    var area: String?
    var roomID: String?
    var exits: Set<String> = []
    var hasRoom = false
    var updated: Date?
    var hasCharacterInfo: Bool {
        name != nil || title != nil || !vitals.isEmpty || experience != nil || potential != nil
    }

    mutating func receive(_ message: GMCPMessage) {
        guard let data = message.object else { return }
        func number(_ keys: [String]) -> Int? {
            for key in keys {
                if let value = data[key] as? NSNumber { return value.intValue }
                if let value = data[key] as? String, let number = Int(value) { return number }
            }
            return nil
        }
        switch message.module.lowercased() {
        case "char.vitals":
            let decoded = Self.decodeVitals(data, number: number)
            guard decoded.contains(where: { ($0.current ?? 0) > 0 || ($0.maximum ?? 0) > 0 }) else { return }
            vitals = decoded
            experience = number(["exp", "experience", "combat_exp"]) ?? experience
            potential = number(["pot", "potential"]) ?? potential
        case "char.status", "char.name":
            name = data["name"] as? String ?? name
            title = data["title"] as? String ?? data["class"] as? String ?? title
            experience = number(["exp", "experience"]) ?? experience
        case "room.info":
            room = data["name"] as? String ?? room
            area = data["area"] as? String ?? area
            roomID = data["hash"] as? String ?? roomID
            hasRoom = true
            if let names = data["exits"] as? [String] { exits = Set(names.map { $0.lowercased() }); hasRoom = true }
            if let mapping = data["exits"] as? [String: Any] { exits = Set(mapping.keys.map { $0.lowercased() }); hasRoom = true }
        default: return
        }
        updated = Date()
    }

    private static func decodeVitals(_ data: [String: Any], number: ([String]) -> Int?) -> [CharacterVital] {
        let metadata = Set(["exp", "experience", "combat_exp", "pot", "potential", "learned_points"])
        let normalizedKeys = Dictionary(data.keys.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var result: [CharacterVital] = []
        for key in data.keys.sorted() where !metadata.contains(key.lowercased()) && !key.lowercased().hasPrefix("max") {
            guard let current = number([key]) else { continue }
            let normalizedKey = key.lowercased()
            let maximumKey = normalizedKeys["max\(normalizedKey)"] ?? normalizedKeys["max_\(normalizedKey)"]
            let maximum = maximumKey.flatMap { number([$0]) }
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            result.append(CharacterVital(id: key, name: label, current: current, maximum: maximum))
        }
        return result
    }
}
