import SwiftUI
import KanbanCodeCore

/// The commands that can start Claude Code besides plain `claude`. The plain
/// row is fixed. Each other row has a name and a command; an empty command is
/// never accepted (the old value comes back). The rules live in
/// `ClaudeLauncherEditing`; the host view saves the list.
struct ClaudeLaunchersSettingsView: View {
    @Binding var launchers: [ClaudeLauncher]

    @State private var newName = ""
    @State private var newCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude launch commands")
                .font(.headline)

            HStack(spacing: 8) {
                Text(ClaudeLauncherEditing.plainName)
                    .frame(maxWidth: 180, alignment: .leading)
                Text(ClaudeLauncherResolver.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("built in")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach($launchers) { $launcher in
                LauncherRow(launcher: $launcher) {
                    launchers.removeAll { $0.id == launcher.id }
                }
            }

            HStack(spacing: 8) {
                TextField("Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                TextField("Command", text: $newCommand, prompt: Text("e.g. codemie-claude"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newCommandIsEmpty)
            }

            Text("A launcher replaces `claude` in the command Kanban Code builds for Claude Code; the flags stay. Pick one per profile in Profiles, or per card when you start it. A card keeps the command it was started with.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var newCommandIsEmpty: Bool {
        newCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard let launcher = ClaudeLauncherEditing.newLauncher(name: newName, command: newCommand) else { return }
        launchers.append(launcher)
        newName = ""
        newCommand = ""
    }
}

/// One editable launcher. The texts are read back when a field is submitted or
/// loses focus, so a half-typed or emptied command never reaches the list.
private struct LauncherRow: View {
    @Binding var launcher: ClaudeLauncher
    let onRemove: () -> Void

    @State private var name = ""
    @State private var command = ""
    private enum Field { case name, command }
    @FocusState private var focused: Field?

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .focused($focused, equals: .name)
                .onSubmit(commit)
            TextField("Command", text: $command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .focused($focused, equals: .command)
                .onSubmit(commit)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove this launcher")
        }
        .onAppear(perform: reload)
        .onChange(of: focused) { commit() }
    }

    private func reload() {
        name = launcher.name
        command = launcher.command
    }

    private func commit() {
        let edited = ClaudeLauncherEditing.edited(launcher, name: name, command: command)
        if edited != launcher { launcher = edited }
        reload()
    }
}
