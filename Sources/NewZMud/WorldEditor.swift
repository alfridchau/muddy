import SwiftUI

struct WorldEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var world: World
    var onSave: (World) -> Void

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
                    Text("Your next world").font(.system(size: 21, weight: .semibold))
                    Text("Save a MUD server to your library.").foregroundStyle(Palette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                field("World name", placeholder: "e.g. 笑傲江湖", text: $world.name)
                field("Description", placeholder: "A familiar corner of the jianghu", text: $world.subtitle)
                HStack(alignment: .top, spacing: 12) {
                    field("Hostname", placeholder: "mud.example.com", text: $world.host)
                    field("Port", placeholder: "4000", text: $world.port).frame(width: 90)
                }
            }
            Text("Use the current host and port provided by your MUD. For the local game, enter 127.0.0.1 and port 6666. Text encoding can be changed per world in Automation settings.")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save world") {
                    world.name = world.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    world.host = world.host.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(world)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.jade)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
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
}
