import Foundation

/// One Claude Code config directory (`~/.claude`, `~/.claude-Client`, ...).
/// The directory is the identity: the account inside it is not tracked.
///
/// Two independent switches:
/// - `enabled`: the app reads the profile's transcripts and shows its cards.
///   It never writes into the profile for this.
/// - `integration`: the app may edit the profile's `settings.json` (hooks,
///   statusline wrapper, vault guard, bundled skill).
public struct ClaudeProfile: Codable, Sendable, Equatable, Identifiable {
    /// Normalized absolute config directory. Also the identity.
    public var path: String
    public var name: String
    public var colorHex: String?
    public var enabled: Bool
    public var integration: Bool

    public var id: String { path }

    public init(
        path: String,
        name: String? = nil,
        colorHex: String? = nil,
        enabled: Bool = false,
        integration: Bool = false,
        home: String = NSHomeDirectory()
    ) {
        let normalizedPath = Self.normalized(path, home: home)
        self.path = normalizedPath
        self.name = name ?? Self.defaultName(forPath: normalizedPath)
        self.colorHex = colorHex
        self.enabled = enabled
        self.integration = integration
    }

    public var projectsDirectory: String { path + "/projects" }
    public var settingsPath: String { path + "/settings.json" }

    /// `~/.claude`: always enabled, cannot be switched off.
    public var isDefault: Bool {
        path == Self.normalized("~/.claude")
    }

    /// A config directory must be a folder of its own. The home folder, `/`
    /// or a folder that contains the home folder would make the app read
    /// `<home>/projects` and write `<home>/settings.json`. A symlink is
    /// checked by where it points as well.
    public func isSafeLocation(home: String = NSHomeDirectory()) -> Bool {
        Self.isSafeLocation(path, home: home)
            && Self.isSafeLocation((path as NSString).resolvingSymlinksInPath, home: home)
    }

    public static func isSafeLocation(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let candidate = normalized(path, home: home)
        let homePath = normalized(home, home: home)
        let resolvedHome = (homePath as NSString).resolvingSymlinksInPath
        guard candidate != "/" else { return false }
        for h in [homePath, resolvedHome] {
            if candidate == h || h.hasPrefix(candidate + "/") { return false }
        }
        return true
    }

    /// False when the folder was deleted after the profile was registered.
    public var exists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - Decoding (per field, one bad value never drops the profile)

    private enum CodingKeys: String, CodingKey {
        case path, name, colorHex, enabled, integration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A profile without a path has no identity: that one is an error.
        let rawPath = try c.decode(String.self, forKey: .path)
        path = Self.normalized(rawPath)
        let storedName = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        name = (storedName?.isEmpty == false ? storedName : nil) ?? Self.defaultName(forPath: path)
        colorHex = (try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? nil
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        integration = (try? c.decodeIfPresent(Bool.self, forKey: .integration)) ?? false
    }

    // MARK: - Paths

    /// Expands `~`, standardizes the path and drops a trailing slash.
    public static func normalized(_ path: String, home: String = NSHomeDirectory()) -> String {
        var expanded = path
        if expanded == "~" {
            expanded = home
        } else if expanded.hasPrefix("~/") {
            expanded = home + String(expanded.dropFirst(1))
        }
        var standardized = (expanded as NSString).standardizingPath
        while standardized.count > 1, standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }

    /// `.claude` is `default`, `.claude-Client` is `Client`, anything
    /// else is the last path component.
    public static func defaultName(forPath path: String) -> String {
        let last = (normalized(path) as NSString).lastPathComponent
        if last == ".claude" { return "default" }
        if last.hasPrefix(".claude-"), last.count > ".claude-".count {
            return String(last.dropFirst(".claude-".count))
        }
        return last
    }

    /// Paths of `~/.claude` and `~/.claude-*` directories that contain a
    /// `projects` directory. Files such as `.claude.json` are ignored.
    public static func discover(home: String = NSHomeDirectory()) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: home) else { return [] }
        var found: [String] = []
        for entry in entries.sorted() where entry == ".claude" || entry.hasPrefix(".claude-") {
            let dir = home + "/" + entry
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            var projectsIsDirectory: ObjCBool = false
            guard fm.fileExists(atPath: dir + "/projects", isDirectory: &projectsIsDirectory),
                  projectsIsDirectory.boolValue else { continue }
            found.append(normalized(dir, home: home))
        }
        return found
    }

    /// Stored profiles are kept in order (also those whose folder is gone), except
    /// those whose path is the home folder or above it.
    /// Each found path that is not stored is appended with both switches off.
    /// The default profile is added when absent, and always comes back enabled.
    public static func merged(
        stored: [ClaudeProfile],
        found: [String],
        home: String = NSHomeDirectory()
    ) -> [ClaudeProfile] {
        let defaultPath = normalized("~/.claude", home: home)
        var result: [ClaudeProfile] = []
        var seen = Set<String>()
        for profile in stored {
            guard profile.isSafeLocation(home: home) else {
                KanbanCodeLog.warn("profiles", "Ignoring profile \(profile.path): it is the home folder or contains it")
                continue
            }
            guard seen.insert(profile.path).inserted else { continue }
            var copy = profile
            if copy.path == defaultPath { copy.enabled = true }
            result.append(copy)
        }
        for raw in found {
            let path = normalized(raw, home: home)
            guard isSafeLocation(path, home: home), seen.insert(path).inserted else { continue }
            let isDefault = path == defaultPath
            result.append(ClaudeProfile(
                path: path, enabled: isDefault, integration: isDefault, home: home))
        }
        if !seen.contains(defaultPath) {
            result.insert(
                ClaudeProfile(path: defaultPath, enabled: true, integration: true, home: home),
                at: 0)
        }
        return result
    }

    /// The `projects` directory of the profile a transcript lives in, or nil
    /// when the path does not have the `<config>/projects/<folder>/<file>` layout.
    public static func projectsDirectory(ofTranscript path: String) -> String? {
        configDirectory(ofTranscript: path).map { $0 + "/projects" }
    }

    /// For `<config>/projects/<folder>/<file>` returns `<config>`, else nil.
    public static func configDirectory(ofTranscript path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        // …/<config>/projects/<folder>/<file>: "projects" sits third from the end.
        guard parts[parts.count - 3] == "projects" else { return nil }
        let configParts = parts[0..<(parts.count - 3)]
        guard !configParts.isEmpty else { return nil }
        return "/" + configParts.joined(separator: "/")
    }
}

extension Settings {
    /// `effectiveClaudeProfiles` of the settings file in `kanbanHome`; the
    /// default profile alone when the file is missing or unreadable.
    public static func readEffectiveClaudeProfiles(kanbanHome: String = HookRestorer.defaultKanbanHome) -> [ClaudeProfile] {
        let path = (kanbanHome as NSString).appendingPathComponent("settings.json")
        let settings = FileManager.default.contents(atPath: path)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
        return (settings ?? Settings()).effectiveClaudeProfiles
    }

    /// The profiles the app works with: the stored list plus the profile
    /// folders found on disk (new ones start switched off).
    public var effectiveClaudeProfiles: [ClaudeProfile] {
        ClaudeProfile.merged(stored: claudeProfiles, found: ClaudeProfile.discover())
    }
}
