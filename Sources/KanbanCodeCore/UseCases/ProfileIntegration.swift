import Foundation

/// Switches the Kanban integration of one Claude profile on or off by editing
/// its `settings.json`: the Kanban hooks, the statusline (wrapped around the
/// user's own, never replacing it), the vault and permission hooks, and the
/// bundled `kanban-code` skill link.
///
/// Other tools' hooks and every other key stay as they are. A `settings.json`
/// that is not a JSON object is left untouched and reported.
public enum ProfileIntegration {

    public enum Failure: LocalizedError, Equatable {
        case unsafeLocation(String)

        public var errorDescription: String? {
            switch self {
            case .unsafeLocation(let path):
                "\(path) is the home folder or contains it, not a Claude config folder"
            }
        }
    }

    /// Adds Kanban's entries to the profile. Idempotent.
    public static func apply(
        _ profile: ClaudeProfile,
        kanbanHome: String = HookRestorer.defaultKanbanHome,
        repoRoot: String? = nil,
        home: String = NSHomeDirectory()
    ) throws {
        guard profile.isSafeLocation(home: home) else { throw Failure.unsafeLocation(profile.path) }
        let settings = profile.settingsPath
        // Throws `unreadableSettings` before anything is written.
        try HookManager.install(
            for: .claude, settingsPath: settings,
            hookScriptPath: (kanbanHome as NSString).appendingPathComponent("hook.sh"),
            recordsOptIn: profile.isDefault)
        try HookManager.installStatusLine(
            settingsPath: settings,
            scriptPath: (kanbanHome as NSString).appendingPathComponent("statusline.sh"))
        try VaultHook.install(
            settingsPath: settings,
            scriptPath: (kanbanHome as NSString).appendingPathComponent("vault-hook.sh"))
        try PermissionHook.install(
            settingsPath: settings,
            scriptPath: (kanbanHome as NSString).appendingPathComponent("permission-hook.sh"))
        ChatBootstrap.ensureSkillSymlink(skillsDirectory: profile.path + "/skills", repoRoot: repoRoot)
    }

    /// Takes out exactly what `apply` added and puts the original `statusLine` back.
    public static func remove(
        _ profile: ClaudeProfile,
        kanbanHome: String = HookRestorer.defaultKanbanHome,
        home: String = NSHomeDirectory()
    ) throws {
        guard profile.isSafeLocation(home: home) else { throw Failure.unsafeLocation(profile.path) }
        let settings = profile.settingsPath
        guard FileManager.default.fileExists(atPath: settings) else {
            ChatBootstrap.removeSkillSymlink(skillsDirectory: profile.path + "/skills")
            return
        }
        // Does not record an opt-out for the default profile.
        try HookManager.uninstall(for: .claude, settingsPath: settings)
        try HookManager.uninstallStatusLine(settingsPath: settings)
        try VaultHook.uninstall(settingsPath: settings)
        try PermissionHook.uninstall(settingsPath: settings)
        try dropEmptyHooksKey(settings)
        ChatBootstrap.removeSkillSymlink(skillsDirectory: profile.path + "/skills")
    }

    /// Whether the profile's settings call the Kanban hook script for every event.
    public static func isApplied(_ profile: ClaudeProfile) -> Bool {
        HookManager.isInstalled(for: .claude, settingsPath: profile.settingsPath)
    }

    /// `hooks: {}` left after the removals is not something the user wrote.
    private static func dropEmptyHooksKey(_ path: String) throws {
        guard let data = FileManager.default.contents(atPath: path),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any], hooks.isEmpty else { return }
        root.removeValue(forKey: "hooks")
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try HookRestorer.writeSettings(out, to: path)
    }
}
