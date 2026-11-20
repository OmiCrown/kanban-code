import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ProfileIntegration")
struct ProfileIntegrationTests {
    private struct Fixture {
        let root: String
        let profile: ClaudeProfile
        let kanbanHome: String
        let repo: String
        var settingsPath: String { profile.settingsPath }
    }

    private func makeFixture(settings: Any? = nil, raw: String? = nil) throws -> Fixture {
        let root = NSTemporaryDirectory() + "kanban-code-integration-\(UUID().uuidString)"
        let fm = FileManager.default
        let profile = ClaudeProfile(path: root + "/.claude-A", enabled: true, integration: true, home: root)
        try fm.createDirectory(atPath: profile.path + "/projects", withIntermediateDirectories: true)
        let repo = root + "/repo"
        try fm.createDirectory(atPath: repo + "/.claude/skills/kanban-code", withIntermediateDirectories: true)
        try "skill".write(toFile: repo + "/.claude/skills/kanban-code/SKILL.md", atomically: true, encoding: .utf8)
        if let settings {
            try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
                .write(to: URL(fileURLWithPath: profile.settingsPath))
        } else if let raw {
            try raw.write(toFile: profile.settingsPath, atomically: true, encoding: .utf8)
        }
        return Fixture(root: root, profile: profile, kanbanHome: root + "/.kanban-code", repo: repo)
    }

    /// Another tool's hook, a foreign statusline and unrelated keys.
    private var original: [String: Any] {
        [
            "model": "opus",
            "permissions": ["allow": ["Bash(ls:*)"]],
            "statusLine": ["type": "command", "command": "usage-tracker --short", "refreshInterval": 60],
            "hooks": [
                "Stop": [["matcher": "", "hooks": [["type": "command", "command": "/usr/local/bin/other-tool"]]]],
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "/opt/guard.sh"]]]],
            ],
        ]
    }

    private func read(_ path: String) throws -> [String: Any] {
        let data = try #require(FileManager.default.contents(atPath: path))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func commands(_ root: [String: Any], event: String) -> [String] {
        let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    @Test func applyAddsKanbanAndKeepsOthers() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        let root = try read(f.settingsPath)
        #expect(commands(root, event: "Stop").contains("/usr/local/bin/other-tool"))
        #expect(commands(root, event: "Stop").contains { $0.contains(".kanban-code/hook.sh") })
        #expect(commands(root, event: "PreToolUse").contains("/opt/guard.sh"))
        #expect(commands(root, event: "PreToolUse").contains { $0.contains(VaultHook.marker) })
        #expect(commands(root, event: PermissionHook.event).contains { $0.contains(PermissionHook.marker) })
        let line = try #require(root["statusLine"] as? [String: Any])
        #expect((line["command"] as? String)?.hasSuffix(" --chain 'usage-tracker --short'") == true)
        #expect(line["refreshInterval"] as? Int == 60)
        #expect(root["model"] as? String == "opus")
        #expect(ProfileIntegration.isApplied(f.profile))
    }

    @Test func applyToAProfileDoesNotOptTheDefaultProfileIn() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        #expect(HookRestorer.recordedOptIn(for: .claude, kanbanHome: f.kanbanHome) == nil)
    }

    @Test func removeRestoresSettingsExactly() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        try ProfileIntegration.remove(f.profile, kanbanHome: f.kanbanHome)
        #expect(NSDictionary(dictionary: try read(f.settingsPath)).isEqual(to: original))
        #expect(!ProfileIntegration.isApplied(f.profile))
    }

    @Test func removeFromSettingsWithoutHooksLeavesNoHooksKey() throws {
        let f = try makeFixture(settings: ["model": "opus"])
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        try ProfileIntegration.remove(f.profile, kanbanHome: f.kanbanHome)
        #expect(NSDictionary(dictionary: try read(f.settingsPath)).isEqual(to: ["model": "opus"]))
    }

    @Test func applyTwiceIsIdempotent() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        let once = try read(f.settingsPath)
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        #expect(NSDictionary(dictionary: try read(f.settingsPath)).isEqual(to: once))
    }

    @Test(arguments: ["", "[1,2]", "not json"])
    func unparseableSettingsThrowsAndIsUntouched(content: String) throws {
        let f = try makeFixture(raw: content)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        #expect(throws: (any Error).self) {
            try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        }
        #expect(try String(contentsOfFile: f.settingsPath, encoding: .utf8) == content)
    }

    @Test func skillLinkedIntoProfile() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        let link = f.profile.path + "/skills/kanban-code"
        #expect(FileManager.default.fileExists(atPath: link + "/SKILL.md"))
        try ProfileIntegration.remove(f.profile, kanbanHome: f.kanbanHome)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == nil)
        #expect(FileManager.default.fileExists(atPath: f.repo + "/.claude/skills/kanban-code/SKILL.md"))
    }

    @Test func removeKeepsARealSkillFolder() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        let real = f.profile.path + "/skills/kanban-code"
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try "mine".write(toFile: real + "/SKILL.md", atomically: true, encoding: .utf8)
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        try ProfileIntegration.remove(f.profile, kanbanHome: f.kanbanHome)
        #expect(try String(contentsOfFile: real + "/SKILL.md", encoding: .utf8) == "mine")
    }

    @Test func isAppliedReflectsState() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        #expect(!ProfileIntegration.isApplied(f.profile))
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        #expect(ProfileIntegration.isApplied(f.profile))
    }

    @Test func profileWithoutSettingsFileGetsOneCreated() throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        #expect(!FileManager.default.fileExists(atPath: f.settingsPath))
        try ProfileIntegration.apply(f.profile, kanbanHome: f.kanbanHome, repoRoot: f.repo)
        #expect(ProfileIntegration.isApplied(f.profile))
        try ProfileIntegration.remove(f.profile, kanbanHome: f.kanbanHome)
        #expect(!ProfileIntegration.isApplied(f.profile))
    }

    @Test func restoreMissingFillsOnlyIntegrationProfiles() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        var off = f.profile
        off.integration = false
        #expect(HookRestorer.restoreMissing(inProfile: off, kanbanHome: f.kanbanHome).isEmpty)
        #expect(!ProfileIntegration.isApplied(f.profile))
        let restored = HookRestorer.restoreMissing(inProfile: f.profile, kanbanHome: f.kanbanHome)
        #expect(!restored.isEmpty)
        #expect(ProfileIntegration.isApplied(f.profile))
        #expect(commands(try read(f.settingsPath), event: "Stop").contains("/usr/local/bin/other-tool"))
        // A foreign statusline is not replaced by the restorer.
        let line = try #require(try read(f.settingsPath)["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == "usage-tracker --short")
    }

    @Test func applyAndRemoveRefuseTheHomeFolder() throws {
        let f = try makeFixture(settings: original)
        defer { try? FileManager.default.removeItem(atPath: f.root) }
        let atHome = ClaudeProfile(path: f.root, enabled: true, integration: true, home: f.root)
        let before = try Data(contentsOf: URL(fileURLWithPath: f.settingsPath))
        #expect(throws: ProfileIntegration.Failure.unsafeLocation(f.root)) {
            try ProfileIntegration.apply(atHome, kanbanHome: f.kanbanHome, repoRoot: f.repo, home: f.root)
        }
        #expect(throws: ProfileIntegration.Failure.unsafeLocation(f.root)) {
            try ProfileIntegration.remove(atHome, kanbanHome: f.kanbanHome, home: f.root)
        }
        #expect(!FileManager.default.fileExists(atPath: f.root + "/settings.json"))
        #expect(!FileManager.default.fileExists(atPath: f.root + "/skills"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: f.settingsPath)) == before)
    }
}
