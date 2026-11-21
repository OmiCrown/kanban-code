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
