import SwiftUI
import KanbanCodeCore

/// Settings > Profiles: which Claude config directories (`~/.claude`,
/// `~/.claude-*`) show their cards on the board, and in which of them Kanban
/// Code may edit `settings.json` (hooks, statusline, vault guard, skill).
struct ProfilesSettingsView: View {
    @State private var profiles: [ClaudeProfile] = []
    @State private var launchers: [ClaudeLauncher] = []
    /// Found on disk but not confirmed by the owner yet.
    @State private var newPaths: Set<String> = []
    @State private var errors: [String: String] = [:]
    @State private var working: Set<String> = []
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    private let settingsStore = SettingsStore()

    private static let palette: [(name: String, hex: String)] = [
        ("Blue", "#3B82F6"), ("Green", "#22C55E"), ("Orange", "#F97316"),
        ("Purple", "#A855F7"), ("Pink", "#EC4899"), ("Teal", "#14B8A6"),
    ]

    var body: some View {
        Form {
            Section {
                Text("Claude Code keeps its sessions in a config directory. Each directory found here can show its cards on the board, labelled with its name. Kanban Code reads a directory's transcripts only while Show is on, and never writes to it for that.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($profiles) { $profile in
                row(for: $profile)
            }
            if profiles.isEmpty && loaded {
                Text("No Claude profile directory found.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await load() }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for profile: Binding<ClaudeProfile>) -> some View {
        let value = profile.wrappedValue
        Section {
            HStack(spacing: 8) {
                colorMenu(for: profile)
                TextField("Name", text: profile.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onChange(of: value.name) { scheduleSave() }
                if newPaths.contains(value.path) {
                    badge("new", color: .blue)
                }
                if !value.exists {
                    badge("missing", color: .orange)
                }
                Spacer()
                Text(abbreviated(value.path))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Toggle("Show on the board", isOn: Binding(
                get: { value.enabled },
                set: { profile.wrappedValue.enabled = $0; scheduleSave() }))
                .disabled(value.isDefault)
            if value.isDefault {
                Text("The default profile is always shown.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Toggle("Kanban integration", isOn: Binding(
                    get: { value.integration },
                    set: { setIntegration($0, for: value.path) }))
                    .disabled(value.isDefault || !value.exists || working.contains(value.path))
                if working.contains(value.path) {
                    ProgressView().controlSize(.small)
                }
            }
            Text(value.isDefault
                 ? "Hooks and the statusline of the default profile are set in Assistants."
                 : "Adds the Kanban hooks, a statusline that records context usage (your own statusline keeps running, wrapped), the vault guard and the kanban-code skill to \(abbreviated(value.settingsPath)). Turning it off removes exactly these and restores your statusline.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            launcherPicker(for: profile)
            githubFields(for: profile)

            if let error = errors[value.path] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    /// The command new cards of this profile's projects start with. An id that
    /// names no launcher shows as Claude Code (it launches plain) and stays
    /// stored until the user picks something.
    private func launcherPicker(for profile: Binding<ClaudeProfile>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Launch with", selection: Binding<String?>(
                get: {
                    ClaudeLauncherEditing.popupSelection(
                        launcherId: profile.wrappedValue.launcherId, launchers: launchers)
                },
                set: { profile.wrappedValue.launcherId = $0; scheduleSave() })) {
                Text(ClaudeLauncherEditing.plainName).tag(String?.none)
                ForEach(launchers) { launcher in
                    Text(launcher.name).tag(String?.some(launcher.id))
                }
            }
            Text("The default command for cards started in this profile's project folders. A card can still pick another when it starts. Add commands in Assistants.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// The GitHub account of the profile's repositories. A repository inside
    /// one of the folders whose owner is not listed is flagged on its card and
    /// is not merged.
    @ViewBuilder
    private func githubFields(for profile: Binding<ClaudeProfile>) -> some View {
        TextField("GitHub login", text: Binding(
            get: { profile.wrappedValue.githubUser ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                profile.wrappedValue.githubUser = trimmed.isEmpty ? nil : trimmed
                scheduleSave()
            }), prompt: Text("e.g. omi-client"))
            .textFieldStyle(.roundedBorder)
        ListField(title: "Project folders", prompt: "~/Repos/Client", values: Binding(
            get: { profile.wrappedValue.projectRoots },
            set: {
                profile.wrappedValue.projectRoots = $0.map { ClaudeProfile.normalized($0) }
                scheduleSave()
            }))
        ListField(title: "GitHub owners", prompt: "client, client-app", values: Binding(
            get: { profile.wrappedValue.githubOwners },
            set: { profile.wrappedValue.githubOwners = $0; scheduleSave() }))
        Text("Repositories inside the project folders run gh as this login (it must be signed in: gh auth login). A repository there whose owner is not in the list is flagged and its pull requests are not merged. Empty list: no owner check.")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private func colorMenu(for profile: Binding<ClaudeProfile>) -> some View {
        Menu {
            Button("Automatic") { profile.wrappedValue.colorHex = nil; scheduleSave() }
            ForEach(Self.palette, id: \.hex) { entry in
                Button(entry.name) { profile.wrappedValue.colorHex = entry.hex; scheduleSave() }
            }
        } label: {
            Circle()
                .fill(profile.wrappedValue.displayColor)
                .frame(width: 14, height: 14)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Colour of the profile label")
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Loading and saving

    private func load() async {
        let settings = try? await settingsStore.read()
        let stored = settings?.claudeProfiles ?? []
        let found = ClaudeProfile.discover()
        let merged = ClaudeProfile.merged(stored: stored, found: found)
        let known = Set(stored.map(\.path))
        newPaths = Set(merged.filter { !known.contains($0.path) && !$0.isDefault }.map(\.path))
        profiles = merged
        launchers = settings?.claudeLaunchers ?? []
        loaded = true
    }

    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        let snapshot = profiles
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await save(snapshot)
        }
    }

    private func save(_ snapshot: [ClaudeProfile]) async {
        guard var settings = try? await settingsStore.read() else { return }
        settings.claudeProfiles = snapshot
        try? await settingsStore.write(settings)
        NotificationCenter.default.post(name: .kanbanCodeSettingsChanged, object: nil)
    }

    // MARK: - Integration

    /// Edits the profile's `settings.json` off the main actor. On a failure
    /// the switch stays where it was and the reason is shown under the row.
    private func setIntegration(_ on: Bool, for path: String) {
        guard let index = profiles.firstIndex(where: { $0.path == path }) else { return }
        let profile = profiles[index]
        guard profile.integration != on else { return }
        errors[path] = nil
        working.insert(path)
        Task {
            let failure: String? = await Task.detached {
                do {
                    if on { try ProfileIntegration.apply(profile) } else { try ProfileIntegration.remove(profile) }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            working.remove(path)
            if let failure {
                errors[path] = failure
                return
            }
            if let current = profiles.firstIndex(where: { $0.path == path }) {
                profiles[current].integration = on
            }
            scheduleSave()
        }
    }
}

/// A comma-separated list in a text field. The list is read back when the
/// field is submitted or loses focus, so a comma typed on the way is kept.
private struct ListField: View {
    let title: String
    let prompt: String
    @Binding var values: [String]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { text = values.joined(separator: ", ") }
            .onSubmit(commit)
            .onChange(of: focused) { if !focused { commit() } }
    }

    private func commit() {
        let parsed = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parsed != values { values = parsed }
        text = parsed.joined(separator: ", ")
    }
}
