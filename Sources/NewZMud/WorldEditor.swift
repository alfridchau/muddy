import SwiftUI

struct WorldEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var world: World
    @State private var encoding: MUDTextEncoding
    var onSave: (World, MUDTextEncoding, Bool) -> Void

    init(world: World, encoding: MUDTextEncoding, onSave: @escaping (World, MUDTextEncoding, Bool) -> Void) {
        _world = State(initialValue: world)
        _encoding = State(initialValue: encoding)
        self.onSave = onSave
    }

    private var isValid: Bool {
        !world.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !world.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (UInt16(world.port) ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "globe.asia.australia")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Palette.jade)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection setup").font(.system(size: 21, weight: .semibold))
                    Text("Add the server details provided by your MUD.").foregroundStyle(Palette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                field("World name", placeholder: "e.g. 笑傲江湖", text: $world.name)
                field("Description", placeholder: "A familiar corner of the jianghu", text: $world.subtitle)
                HStack(alignment: .top, spacing: 12) {
                    field("Hostname", placeholder: "mud.example.com", text: $world.host)
                    field("Port", placeholder: "4000", text: $world.port).frame(width: 90)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text encoding").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                    Picker("Text encoding", selection: $encoding) {
                        ForEach(MUDTextEncoding.allCases) { option in Text(option.title).tag(option) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("After connecting, sign-in prompts appear in the game terminal. Credentials are not saved. You can change encoding later in this world's Display settings.")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(connect: false) }.disabled(!isValid)
                Button("Save & Connect") { save(connect: true) }
                    .buttonStyle(.borderedProminent).tint(Palette.jade)
                    .keyboardShortcut(.defaultAction).disabled(!isValid)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(Palette.panel)
        .preferredColorScheme(.dark)
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func save(connect: Bool) {
        world.name = world.name.trimmingCharacters(in: .whitespacesAndNewlines)
        world.host = world.host.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(world, encoding, connect)
        dismiss()
    }
}
