import CoreFoundation
import SwiftUI

struct GMCPFieldSummary: Identifiable, Equatable {
    var name: String
    var type: String
    var id: String { name }
}

struct GMCPDiagnosticEntry: Identifiable, Equatable {
    var module: String
    var count: Int
    var lastReceived: Date
    var fields: [GMCPFieldSummary]
    var id: String { module }

    mutating func record(_ message: GMCPMessage, at date: Date) {
        count += 1
        lastReceived = date
        fields = Self.fieldSummaries(message)
    }

    static func fieldSummaries(_ message: GMCPMessage) -> [GMCPFieldSummary] {
        guard let object = message.object else { return [] }
        return object.keys.sorted().prefix(256).map { key in
            GMCPFieldSummary(name: String(key.prefix(120)), type: typeName(object[key] ?? NSNull()))
        }
    }

    private static func typeName(_ value: Any) -> String {
        if value is NSNull { return "Null" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "Boolean" : "Number"
        }
        if value is String { return "String" }
        if value is [Any] { return "Array" }
        if value is [String: Any] { return "Object" }
        return "Other"
    }
}

struct GMCPDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: MUDSession
    @ObservedObject var automation: AutomationStore
    @State private var expandedModules: Set<String> = []
    @State private var showStatSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GMCP diagnostics").font(.system(size: 20, weight: .semibold))
                    Text("Local session metadata only · payload values are excluded")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Configure stats…") { showStatSetup = true }
                    .buttonStyle(.borderedProminent).tint(Palette.jade)
                    .disabled(discoveredStatIDs.isEmpty)
                Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(Palette.jade)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(session.gmcpAvailable ? Palette.jade : Palette.muted).frame(width: 7, height: 7)
                    Text(session.gmcpAvailable ? "GMCP negotiated" : "GMCP not negotiated")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(session.gmcpDiagnostics.reduce(0) { $0 + $1.count }) received")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                Divider()
                Text("Client support advertised").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                Text(MUDSession.clientSupportedGMCPModules.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                Text("Server support reported").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                Text(session.serverSupportedGMCPModules.isEmpty ? "No Core.Supports list received" : session.serverSupportedGMCPModules.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled)
            }
            .padding(12).background(Palette.raised).clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                SectionLabel(title: "Received messages")
                Spacer()
                Text("Module · count · last received").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            if session.gmcpDiagnostics.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 22)).foregroundStyle(Palette.muted)
                    Text("No GMCP messages yet").font(.system(size: 12, weight: .medium))
                    Text(session.gmcpAvailable ? "Waiting for the server to send a message." : "Connect to a GMCP-enabled MUD to inspect its messages.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(session.gmcpDiagnostics) { entry in
                            DisclosureGroup(isExpanded: binding(for: entry.module)) {
                                if entry.fields.isEmpty {
                                    Text("No object fields").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                                } else {
                                    VStack(spacing: 4) {
                                        ForEach(entry.fields) { field in
                                            HStack {
                                                Text(field.name).lineLimit(1)
                                                Spacer()
                                                Text(field.type).foregroundStyle(Palette.muted)
                                            }
                                            .font(.system(size: 10, design: .monospaced))
                                        }
                                    }.padding(.top, 6)
                                }
                            } label: {
                                HStack {
                                    Text(entry.module).font(.system(size: 11, weight: .medium, design: .monospaced))
                                    Spacer()
                                    Text("×\(entry.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                                    Text(entry.lastReceived.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                                }
                            }
                            .padding(10).background(Palette.raised.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 560, height: 590)
        .foregroundStyle(Palette.ink).background(Palette.panel).preferredColorScheme(.dark)
        .sheet(isPresented: $showStatSetup) {
            GMCPStatSetupView(session: session, automation: automation)
        }
    }

    private var discoveredStatIDs: [String] {
        let actual = session.character.vitals.map(\.id)
        let fields = session.gmcpDiagnostics.first { $0.module.caseInsensitiveCompare("Char.Vitals") == .orderedSame }?.fields ?? []
        let numeric = Set(fields.filter { $0.type == "Number" }.map { $0.name.lowercased() })
        let paired = fields.filter { field in
            let key = field.name.lowercased()
            guard field.type == "Number", !key.hasPrefix("max") else { return false }
            return numeric.contains("max\(key)") || numeric.contains("max_\(key)")
        }.map(\.name)
        return Array(Set(actual + paired)).sorted()
    }

    private func binding(for module: String) -> Binding<Bool> {
        Binding(
            get: { expandedModules.contains(module) },
            set: { expanded in
                if expanded { expandedModules.insert(module) }
                else { expandedModules.remove(module) }
            }
        )
    }
}

private struct GMCPStatSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: MUDSession
    @ObservedObject var automation: AutomationStore
    @State private var draft: WorldConfiguration

    init(session: MUDSession, automation: AutomationStore) {
        self.session = session
        self.automation = automation
        _draft = State(initialValue: automation.configuration)
    }

    private var stats: [CharacterVital] {
        let actual = Dictionary(session.character.vitals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fields = session.gmcpDiagnostics.first { $0.module.caseInsensitiveCompare("Char.Vitals") == .orderedSame }?.fields ?? []
        let numeric = Set(fields.filter { $0.type == "Number" }.map { $0.name.lowercased() })
        let discovered = fields.filter { field in
            let key = field.name.lowercased()
            guard field.type == "Number", !key.hasPrefix("max") else { return false }
            return numeric.contains("max\(key)") || numeric.contains("max_\(key)")
        }.map { field -> CharacterVital in
            actual[field.name] ?? CharacterVital(id: field.name,
                                                 name: field.name.replacingOccurrences(of: "_", with: " ").capitalized,
                                                 current: nil, maximum: nil)
        }
        return Array(Dictionary((session.character.vitals + discovered).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private var orderedStats: [CharacterVital] {
        let indices = Dictionary(draft.vitalOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return stats.enumerated().sorted { lhs, rhs in
            let left = indices[lhs.element.id] ?? Int.max
            let right = indices[rhs.element.id] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up character stats").font(.system(size: 20, weight: .semibold))
                Text("Discovered from Char.Vitals · values are not shown here")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Toggle("Hide empty 0 / 0 stats", isOn: $draft.hideEmptyVitals).toggleStyle(.checkbox)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(Array(orderedStats.enumerated()), id: \.element.id) { index, vital in
                        HStack(spacing: 7) {
                            Button { move(vital.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0).buttonStyle(.plain).foregroundStyle(Palette.muted)
                            Button { move(vital.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == orderedStats.count - 1).buttonStyle(.plain).foregroundStyle(Palette.muted)
                            TextField(vital.id, text: labelBinding(for: vital.id)).textFieldStyle(.roundedBorder)
                            Toggle("Show", isOn: visibilityBinding(for: vital.id)).labelsHidden().toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .frame(minHeight: 150)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save settings") {
                    draft.vitalOrder = orderedStats.map(\.id)
                    automation.configuration = draft
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(Palette.jade).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 540, height: 470)
        .foregroundStyle(Palette.ink).background(Palette.panel).preferredColorScheme(.dark)
    }

    private func labelBinding(for id: String) -> Binding<String> {
        Binding(
            get: { draft.vitalLabels.first { $0.field.caseInsensitiveCompare(id) == .orderedSame }?.label ?? "" },
            set: { value in
                if let index = draft.vitalLabels.firstIndex(where: { $0.field.caseInsensitiveCompare(id) == .orderedSame }) {
                    draft.vitalLabels[index].label = value
                } else if !value.isEmpty {
                    draft.vitalLabels.append(VitalLabelRule(field: id, label: value))
                }
            }
        )
    }

    private func visibilityBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !draft.hiddenVitals.contains(id) },
            set: { shown in
                if shown { draft.hiddenVitals.remove(id) }
                else { draft.hiddenVitals.insert(id) }
            }
        )
    }

    private func move(_ id: String, by offset: Int) {
        var ids = orderedStats.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        draft.vitalOrder = ids
    }
}
