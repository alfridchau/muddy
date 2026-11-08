import Foundation
import CoreFoundation

struct AliasRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var name = ""
    var commands = ""
}
struct TriggerRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var pattern = ""
    var commands = ""
}
struct TimerRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = false
    var name = ""
    var interval: Double = 30
    var commands = ""
}
struct KeyRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var key = "F1"
    var command = false
    var option = false
    var control = false
    var shift = false
    var commands = "look"

    var isValid: Bool {
        let function = key.uppercased().hasPrefix("F") && (1...12).contains(Int(key.dropFirst()) ?? 0)
        return function || (key.count == 1 && (command || option || control))
    }
    var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased()
    }
}
struct QuickAction: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var title = ""
    var command = ""
    var symbol = "bolt"

    static let defaults = [
        QuickAction(title: "Look around", command: "look", symbol: "eye"),
        QuickAction(title: "Inventory", command: "inventory", symbol: "bag"),
        QuickAction(title: "Character sheet", command: "score", symbol: "person.text.rectangle"),
        QuickAction(title: "Help", command: "help", symbol: "questionmark.circle")
    ]
}
struct VitalLabelRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var field = ""
    var label = ""
}
struct ExitCommandRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var exit = ""
    var command = ""
}
enum LoginPromptKind: String, Codable, CaseIterable, Identifiable {
    case username, password, ready
    var id: String { rawValue }
    var title: String {
        switch self {
        case .username: "Username prompt"
        case .password: "Password prompt"
        case .ready: "In game / ready"
        }
    }
}
struct LoginPromptRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: LoginPromptKind = .username
    var pattern = ""
}
enum MUDTextEncoding: String, Codable, CaseIterable, Identifiable {
    case utf8, gbk, shiftJIS, windows1252
    var id: String { rawValue }
    var title: String {
        switch self {
        case .utf8: "UTF-8"
        case .gbk: "GBK / GB18030"
        case .shiftJIS: "Shift JIS"
        case .windows1252: "Windows-1252"
        }
    }
    var foundationEncoding: String.Encoding {
        switch self {
        case .utf8: return String.Encoding.utf8
        case .gbk:
            let value = CFStringConvertIANACharSetNameToEncoding("GB18030" as CFString)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(value))
        case .shiftJIS: return String.Encoding.shiftJIS
        case .windows1252: return String.Encoding.windowsCP1252
        }
    }
}
enum TerminalTheme: String, Codable, CaseIterable, Identifiable {
    case midnight, paper, amber
    var id: String { rawValue }
    var title: String {
        switch self {
        case .midnight: "Midnight"
        case .paper: "Paper"
        case .amber: "Amber"
        }
    }
}
struct WorldConfiguration: Codable, Equatable {
    var aliases: [AliasRule] = []
    var triggers: [TriggerRule] = []
    var timers: [TimerRule] = []
    var keys: [KeyRule] = []
    var quickActions = QuickAction.defaults
    var vitalLabels: [VitalLabelRule] = []
    var hideEmptyVitals = true
    var vitalOrder: [String] = []
    var hiddenVitals: Set<String> = []
    var exitCommands: [ExitCommandRule] = []
    var loginPrompts: [LoginPromptRule] = []
    var terminalFontSize = 14.0
    var terminalEncoding: MUDTextEncoding = .utf8
    var terminalTheme: TerminalTheme = .midnight
    var walkDelay: Double = 0.4
    var autoReconnect = false

    private enum CodingKeys: String, CodingKey {
        case aliases, triggers, timers, keys, quickActions, vitalLabels, hideEmptyVitals, vitalOrder, hiddenVitals
        case exitCommands, loginPrompts, terminalFontSize, terminalEncoding, terminalTheme, walkDelay, autoReconnect
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        aliases = try values.decodeIfPresent([AliasRule].self, forKey: .aliases) ?? []
        triggers = try values.decodeIfPresent([TriggerRule].self, forKey: .triggers) ?? []
        timers = try values.decodeIfPresent([TimerRule].self, forKey: .timers) ?? []
        keys = try values.decodeIfPresent([KeyRule].self, forKey: .keys) ?? []
        quickActions = try values.decodeIfPresent([QuickAction].self, forKey: .quickActions) ?? QuickAction.defaults
        vitalLabels = try values.decodeIfPresent([VitalLabelRule].self, forKey: .vitalLabels) ?? []
        hideEmptyVitals = try values.decodeIfPresent(Bool.self, forKey: .hideEmptyVitals) ?? true
        vitalOrder = try values.decodeIfPresent([String].self, forKey: .vitalOrder) ?? []
        hiddenVitals = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenVitals) ?? []
        exitCommands = try values.decodeIfPresent([ExitCommandRule].self, forKey: .exitCommands) ?? []
        loginPrompts = try values.decodeIfPresent([LoginPromptRule].self, forKey: .loginPrompts) ?? []
        terminalFontSize = try values.decodeIfPresent(Double.self, forKey: .terminalFontSize) ?? 14
        terminalEncoding = try values.decodeIfPresent(MUDTextEncoding.self, forKey: .terminalEncoding) ?? .utf8
        terminalTheme = try values.decodeIfPresent(TerminalTheme.self, forKey: .terminalTheme) ?? .midnight
        walkDelay = try values.decodeIfPresent(Double.self, forKey: .walkDelay) ?? 0.4
        autoReconnect = try values.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? false
    }
}

@MainActor
final class AutomationStore: ObservableObject {
    @Published var configuration = WorldConfiguration() { didSet { save() } }
    private var worldID: UUID?
    private var loading = false

    func load(_ id: UUID) {
        loading = true
        worldID = id
        let data = UserDefaults.standard.data(forKey: "worldConfiguration.\(id.uuidString)")
        configuration = data.flatMap { try? JSONDecoder().decode(WorldConfiguration.self, from: $0) } ?? WorldConfiguration()
        loading = false
    }
    private func save() {
        guard !loading, let worldID, let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: "worldConfiguration.\(worldID.uuidString)")
    }
}

enum CommandExpansionError: LocalizedError {
    case invalidPath, tooManyCommands, recursiveAlias
    var errorDescription: String? {
        switch self {
        case .invalidPath: return "Use a path such as /walk 2n3e, with n, s, e, w, ne, nw, se, sw, u, or d."
        case .tooManyCommands: return "A sequence can contain at most 100 commands."
        case .recursiveAlias: return "Alias expansion stopped because the aliases form a loop."
        }
    }
}

enum CommandExpansion {
    static func actions(_ source: String) -> [String] {
        source.components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func substitute(_ source: String, arguments: [String], all: String, match: String = "") -> String {
        let expression = try! NSRegularExpression(pattern: #"\$(\*|[0-9])"#)
        let string = source as NSString
        var result = source
        for token in expression.matches(in: source, range: NSRange(location: 0, length: string.length)).reversed() {
            let key = string.substring(with: token.range(at: 1))
            let value: String
            if key == "*" { value = all }
            else if key == "0" { value = match }
            else { let index = (Int(key) ?? 0) - 1; value = arguments.indices.contains(index) ? arguments[index] : "" }
            if let range = Range(token.range, in: result) { result.replaceSubrange(range, with: value) }
        }
        return result
    }

    static func aliases(_ source: String, rules: [AliasRule], depth: Int = 0) throws -> [String] {
        guard depth < 10 else { throw CommandExpansionError.recursiveAlias }
        var expanded: [String] = []
        for command in actions(source) {
            let words = command.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            if let name = words.first, let rule = rules.first(where: { $0.enabled && $0.name == name }) {
                let arguments = words.count > 1 ? String(words[1]) : ""
                let substituted = substitute(rule.commands, arguments: arguments.split(whereSeparator: \.isWhitespace).map(String.init), all: arguments)
                expanded += try aliases(substituted, rules: rules, depth: depth + 1)
            } else { expanded.append(command) }
            guard expanded.count <= 100 else { throw CommandExpansionError.tooManyCommands }
        }
        return expanded
    }

    static func walk(_ source: String) throws -> [String] {
        let path = source.lowercased().filter { !$0.isWhitespace && $0 != "," }
        let regex = try! NSRegularExpression(pattern: #"([0-9]*)(ne|nw|se|sw|n|s|e|w|u|d)"#)
        let string = path as NSString
        var position = 0
        var commands: [String] = []
        for match in regex.matches(in: path, range: NSRange(location: 0, length: string.length)) {
            guard match.range.location == position else { throw CommandExpansionError.invalidPath }
            position += match.range.length
            let countText = string.substring(with: match.range(at: 1))
            let count = countText.isEmpty ? 1 : (Int(countText) ?? 0)
            guard count > 0 else { throw CommandExpansionError.invalidPath }
            guard count <= 100 && commands.count + count <= 100 else { throw CommandExpansionError.tooManyCommands }
            let direction = string.substring(with: match.range(at: 2))
            commands.append(contentsOf: Array(repeating: direction, count: count))
        }
        guard position == string.length, !commands.isEmpty else { throw CommandExpansionError.invalidPath }
        return commands
    }

    static func trigger(_ rule: TriggerRule, line: String) -> [String]? {
        guard rule.enabled, !rule.pattern.isEmpty, let regex = try? NSRegularExpression(pattern: rule.pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        let text = line as NSString
        let captures = (1..<match.numberOfRanges).map { index -> String in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : text.substring(with: range)
        }
        return actions(substitute(rule.commands, arguments: captures, all: captures.joined(separator: " "), match: text.substring(with: match.range)))
    }
}

struct CommandRecall {
    private(set) var index: Int?
    private var draft = ""
    mutating func reset() { index = nil; draft = "" }
    mutating func move(up: Bool, current: String, history: [String]) -> String {
        guard !history.isEmpty else { return current }
        if up {
            if index == nil { draft = current; index = history.count }
            index = max(0, (index ?? history.count) - 1)
            return history[index!]
        }
        guard let position = index else { return current }
        if position + 1 >= history.count { index = nil; return draft }
        index = position + 1
        return history[position + 1]
    }
}

struct CommandCompletion {
    private var original = ""
    private var candidates: [String] = []
    private var index = -1
    private var last = ""
    mutating func reset() { self = CommandCompletion() }
    mutating func complete(_ input: String, words: [String], backwards: Bool = false) -> String {
        if input != last || candidates.isEmpty {
            original = input
            let prefix = input.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? ""
            guard !prefix.isEmpty else { return input }
            let base = String(input.dropLast(prefix.count))
            candidates = Array(Set(words)).filter { $0.lowercased().hasPrefix(prefix.lowercased()) && $0 != prefix }.sorted().map { base + $0 }
            index = -1
        }
        guard !candidates.isEmpty else { return input }
        if index < 0 { index = backwards ? candidates.count - 1 : 0 }
        else { index = (index + (backwards ? candidates.count - 1 : 1)) % candidates.count }
        last = candidates[index]
        return last
    }
}

struct ReconnectPolicy {
    static func delay(for attempt: Int) -> Int? {
        guard (1...5).contains(attempt) else { return nil }
        return min(30, 3 * (1 << (attempt - 1)))
    }
}
