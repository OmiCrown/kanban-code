import SwiftUI
import KanbanCodeCore

/// The "Import sessions" sheet: running Claude instances and finished
/// sessions the user can bring onto the board as ordinary cards. It reads
/// what the planner offers and dispatches one `.importSessions` action.
struct ImportSessionsView: View {
    let store: BoardStore
    let onClose: () -> Void

    @State private var offer: ImportOffer?
    @State private var loadError: String?
    @State private var selection: Set<String> = []
    @State private var query = ""
    @State private var profileFilter: String?
    /// Groups whose rows are all shown, not the first ten.
    @State private var expandedGroups: Set<String> = []

    private static let rowsPerGroup = 10

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
        .task { await load() }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import sessions").font(.app(.headline))
            Text("Pick the sessions to bring onto the board. Nothing is added until you press Import.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            HStack {
                TextField("Search the first prompt", text: $query)
                    .textFieldStyle(.roundedBorder)
                if !store.state.labelledProfiles.isEmpty {
                    Picker("Profile", selection: $profileFilter) {
                        Text("All Profiles").tag(String?.none)
                        ForEach(store.state.labelledProfiles) { profile in
                            Text(profile.name).tag(String?.some(profile.path))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            VStack(spacing: 8) {
                Text("Could not read the sessions").font(.app(.headline))
                Text(loadError).font(.app(.caption)).foregroundStyle(.secondary)
                Button("Try Again") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let offer {
            let running = offer.running.filter(matches)
            let groups = offer.finished.compactMap(filtered)
            if running.isEmpty && groups.isEmpty {
                Text("Nothing to import")
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if !running.isEmpty {
                            sectionTitle("Running in a terminal")
                            ForEach(running) { row($0) }
                            Text("The terminal window stays open. The card starts its own session with --resume, and asks before it does.")
                                .font(.app(.caption2))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 28)
                                .padding(.bottom, 8)
                        }
                        if !groups.isEmpty {
                            sectionTitle("Finished")
                            ForEach(groups) { group in groupView(group) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        } else {
            ProgressView("Reading sessions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(selection.count) selected")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { onClose() }
                .keyboardShortcut(.cancelAction)
            Button("Import \(selection.count)") { importSelected() }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
        }
        .padding(16)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.app(.subheadline, weight: .semibold))
            .padding(.top, 8)
    }

    private func groupView(_ group: ImportGroup) -> some View {
        let showAll = expandedGroups.contains(group.id) || !query.isEmpty
        let visible = showAll ? group.candidates : Array(group.candidates.prefix(Self.rowsPerGroup))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(folderName(group.projectPath)).font(.app(.callout, weight: .medium))
                profilePill(group.profilePath)
                Spacer()
                Button("All") { selection.formUnion(group.candidates.map(\.sessionId)) }
                    .buttonStyle(.link)
                Button("None") { selection.subtract(group.candidates.map(\.sessionId)) }
                    .buttonStyle(.link)
            }
            .font(.app(.caption))
            .help(group.projectPath ?? "")
            .padding(.top, 6)
            ForEach(visible) { row($0, showProfile: false) }
            if visible.count < group.candidates.count {
                Button("Show \(group.candidates.count - visible.count) more") {
                    expandedGroups.insert(group.id)
                }
                .buttonStyle(.link)
                .font(.app(.caption))
                .padding(.leading, 28)
            }
        }
    }

    private func row(_ candidate: ImportCandidate, showProfile: Bool = true) -> some View {
        Toggle(isOn: Binding(
            get: { selection.contains(candidate.sessionId) },
            set: { on in
                if on { selection.insert(candidate.sessionId) } else { selection.remove(candidate.sessionId) }
            }
        )) {
            HStack(spacing: 6) {
                Text(candidate.title).lineLimit(1).font(.app(.callout))
                if showProfile { profilePill(candidate.profilePath) }
                if candidate.isRunning {
                    Text(folderName(candidate.projectPath))
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(candidate.messageCount) msgs")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                Text(candidate.modifiedTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .help(candidate.transcriptPath)
    }

    @ViewBuilder
    private func profilePill(_ path: String?) -> some View {
        if let path, let profile = store.state.labelledProfiles.first(where: { $0.path == path }) {
            ProfilePill(profile: profile)
        }
    }

    // MARK: - Data

    private func folderName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "No project" }
        return (path as NSString).lastPathComponent
    }

    private func matches(_ candidate: ImportCandidate) -> Bool {
        if let profileFilter, candidate.profilePath != profileFilter { return false }
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || candidate.title.localizedCaseInsensitiveContains(text)
    }

    private func filtered(_ group: ImportGroup) -> ImportGroup? {
        let kept = group.candidates.filter(matches)
        guard !kept.isEmpty else { return nil }
        return ImportGroup(projectPath: group.projectPath, profilePath: group.profilePath, candidates: kept)
    }

    private func load() async {
        offer = nil
        loadError = nil
        let held = Set(store.state.links.values.filter { !$0.isTombstone }
            .compactMap { $0.sessionLink?.sessionId })
        let excluded = held.union(store.state.deletedSessionIds)
        let profiles = Settings.readEffectiveClaudeProfiles()
        do {
            let sessions = try await AppComposition.shared.claudeDiscovery.discoverSessions()
            let running = await Task.detached(priority: .userInitiated) {
                RunningSessionReader.read(profiles: profiles)
            }.value
            let result = SessionImportPlanner.plan(
                sessions: sessions, running: running, excludedSessionIds: excluded)
            offer = result
            selection = result.defaultSelection
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func importSelected() {
        guard let offer else { return }
        let everyone = offer.running + offer.finished.flatMap(\.candidates)
        let links = everyone
            .filter { selection.contains($0.sessionId) }
            .map { SessionImportPlanner.makeLink($0) }
        store.dispatch(.importSessions(links))
        onClose()
    }
}
