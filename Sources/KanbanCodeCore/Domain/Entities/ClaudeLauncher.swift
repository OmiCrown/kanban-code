import Foundation

/// A command that starts Claude Code, besides plain `claude` (for example a
/// wrapper that routes requests through another gateway).
public struct ClaudeLauncher: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// The executable that replaces `claude` in the launch command.
    public var command: String

    public init(id: String, name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }

    /// The launcher the app seeds.
    public static let codemie = ClaudeLauncher(
        id: "codemie", name: "Claude Code via CodeMie", command: "codemie-claude")
}

/// Which command a launch uses. Plain `claude` is the string `claude`; a card
/// stores nothing for it (a nil launch command means plain).
public enum ClaudeLauncherResolver {
    public static let plain = "claude"

    /// The command a project starts with by default: the launcher of the
    /// profile whose root contains `path`. Every miss gives plain `claude`.
    public static func defaultCommand(
        forProjectPath path: String?,
        profiles: [ClaudeProfile],
        launchers: [ClaudeLauncher]
    ) -> String {
        guard let path,
              let launcherId = GitHubAccountPolicy.profile(forRepoPath: path, in: profiles)?.launcherId,
              let launcher = launchers.first(where: { $0.id == launcherId })
        else { return plain }
        return launcher.command
    }

    /// What a card keeps: nothing for plain `claude`, else the trimmed command.
    public static func commandToStore(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == plain ? nil : trimmed
    }

    /// The launch command a user's edit of the whole command line stands for:
    /// the first word that is `claude` or a launcher's command, else plain.
    public static func command(fromEdited text: String, launchers: [ClaudeLauncher]) -> String {
        let known = Set([plain] + launchers.map(\.command))
        return text.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first(where: known.contains) ?? plain
    }

    /// `explicit` wins, then what the card stored. A card that already has a
    /// session was started plain, before launchers existed. Otherwise the
    /// project's default.
    public static func forLaunch(
        explicit: String?,
        linkLauncherCommand: String?,
        hasSession: Bool,
        projectPath: String,
        profiles: [ClaudeProfile],
        launchers: [ClaudeLauncher]
    ) -> String {
        if let explicit { return explicit }
        if let linkLauncherCommand { return linkLauncherCommand }
        if hasSession { return plain }
        return defaultCommand(forProjectPath: projectPath, profiles: profiles, launchers: launchers)
    }
}

/// The rules of the launcher list editor in Settings, kept out of the views.
/// An empty command is never accepted: nothing downstream guards it.
public enum ClaudeLauncherEditing {
    /// The name shown for plain `claude`, which is not a list entry.
    public static let plainName = "Claude Code"

    /// A new launcher with a fresh id, or nil when the command is empty.
    /// An empty name falls back to the command.
    public static func newLauncher(name: String, command: String) -> ClaudeLauncher? {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClaudeLauncher(
            id: UUID().uuidString, name: name.isEmpty ? command : name, command: command)
    }

    /// `launcher` with the edited texts: trimmed, the id unchanged (a rename keeps
    /// the profiles that point at it). An empty field keeps its old value.
    public static func edited(_ launcher: ClaudeLauncher, name: String, command: String) -> ClaudeLauncher {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = launcher
        if !name.isEmpty { result.name = name }
        if !command.isEmpty { result.command = command }
        return result
    }

    /// The list to store: texts trimmed, entries with an empty command dropped,
    /// an empty name replaced by the command, an empty or repeated id replaced
    /// by a fresh one.
    public static func cleaned(_ launchers: [ClaudeLauncher]) -> [ClaudeLauncher] {
        var seen = Set<String>()
        var result: [ClaudeLauncher] = []
        for launcher in launchers {
            let command = launcher.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { continue }
            let name = launcher.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var id = launcher.id
            if id.isEmpty || seen.contains(id) { id = UUID().uuidString }
            seen.insert(id)
            result.append(ClaudeLauncher(id: id, name: name.isEmpty ? command : name, command: command))
        }
        return result
    }

    /// The launcher id a profile's popup shows: nil (plain Claude Code) when the
    /// profile has none or names a launcher that no longer exists. The stored id
    /// is not touched.
    public static func popupSelection(launcherId: String?, launchers: [ClaudeLauncher]) -> String? {
        guard let launcherId, launchers.contains(where: { $0.id == launcherId }) else { return nil }
        return launcherId
    }
}
