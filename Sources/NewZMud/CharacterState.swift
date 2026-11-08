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

struct CharacterMeter {
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
    var health = CharacterMeter()
    var innerPower = CharacterMeter()
    var spirit = CharacterMeter()
    var experience: Int?
    var room: String?
    var area: String?
    var exits: Set<String> = []
    var hasRoom = false
    var updated: Date?

    mutating func receive(_ message: GMCPMessage) {
        guard let data = message.object else { return }
        func number(_ keys: String...) -> Int? {
            for key in keys {
                if let value = data[key] as? NSNumber { return value.intValue }
                if let value = data[key] as? String, let number = Int(value) { return number }
            }
            return nil
        }
        switch message.module.lowercased() {
        case "char.vitals":
            health.current = number("hp", "qi") ?? health.current
            health.maximum = number("max_hp", "maxhp", "max_qi") ?? health.maximum
            innerPower.current = number("neili", "mana", "mp") ?? innerPower.current
            innerPower.maximum = number("max_neili", "maxmana", "max_mana", "max_mp") ?? innerPower.maximum
            spirit.current = number("jing", "sp") ?? spirit.current
            spirit.maximum = number("max_jing", "max_sp") ?? spirit.maximum
            experience = number("exp", "experience", "combat_exp") ?? experience
        case "char.status", "char.name":
            name = data["name"] as? String ?? name
            title = data["title"] as? String ?? data["class"] as? String ?? title
            experience = number("exp", "experience") ?? experience
        case "room.info":
            room = data["name"] as? String ?? room
            area = data["area"] as? String ?? area
            if let names = data["exits"] as? [String] { exits = Set(names.map { $0.lowercased() }); hasRoom = true }
            if let mapping = data["exits"] as? [String: Any] { exits = Set(mapping.keys.map { $0.lowercased() }); hasRoom = true }
        default: return
        }
        updated = Date()
    }
}
