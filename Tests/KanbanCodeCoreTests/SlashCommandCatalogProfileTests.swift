import Foundation
import KanbanCodeRemoteKit
import Testing

@testable import KanbanCodeCore

/// A card's skills and commands come from the profile its transcript lives
/// in, not from `~/.claude`.
@Suite("SlashCommandCatalogProfile")
struct SlashCommandCatalogProfileTests {
    private func makeHome() throws -> String {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("slash-profile-\(UUID().uuidString)").resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: root + "/.claude/commands", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root + "/.claude-A/commands", withIntermediateDirectories: true)
        try "---\ndescription: default one\n---\n".write(
            toFile: root + "/.claude/commands/in-default.md", atomically: true, encoding: .utf8)
        try "---\ndescription: profile one\n---\n".write(
            toFile: root + "/.claude-A/commands/in-profile.md", atomically: true, encoding: .utf8)
        return root
    }

    @Test func readsCommandsFromGivenProfile() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let transcript = home + "/.claude-A/projects/-p/s1.jsonl"
        let config = SlashCommandSession.claudeConfigDirectory(
            transcriptPath: transcript, isRush: false, home: home, environment: [:])
        #expect(config == home + "/.claude-A")
        let names = ClaudeCommandFiles.commands(configDirectory: config, cwd: nil, home: home).map(\.name)
        #expect(names.contains("in-profile"))
        #expect(!names.contains("in-default"))
    }

    @Test func nilMeansDefault() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let transcript = home + "/.claude/projects/-p/s1.jsonl"
        let config = SlashCommandSession.claudeConfigDirectory(
            transcriptPath: transcript, isRush: false, home: home, environment: [:])
        #expect(config == nil)
        let names = ClaudeCommandFiles.commands(configDirectory: config, cwd: nil, home: home).map(\.name)
        #expect(names.contains("in-default"))
        #expect(!names.contains("in-profile"))
    }
}
