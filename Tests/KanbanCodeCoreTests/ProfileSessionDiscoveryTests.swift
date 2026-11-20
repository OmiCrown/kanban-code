import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ProfileSessionDiscovery")
struct ProfileSessionDiscoveryTests {
    private func makeHome() throws -> String {
        let dir = NSTemporaryDirectory() + "kanban-code-profiles-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A profile folder with one transcript for `sessionId`, modified at `modified`.
    @discardableResult
    private func makeProfile(
        _ home: String, _ name: String, sessionId: String,
        enabled: Bool = true, modified: Date = .now
    ) throws -> ClaudeProfile {
        let profile = ClaudeProfile(path: home + "/" + name, enabled: enabled, home: home)
        let folder = profile.projectsDirectory + "/-Users-test-project"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let file = folder + "/\(sessionId).jsonl"
        try [
            #"{"type":"user","sessionId":"\#(sessionId)","message":{"content":"Hello \#(sessionId)"},"cwd":"/Users/test/project"}"#,
            #"{"type":"assistant","sessionId":"\#(sessionId)","message":{"content":[{"type":"text","text":"Hi"}]}}"#,
        ].joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file)
        return profile
    }

    @Test func readsEveryEnabledProfile() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let a = try makeProfile(home, ".claude", sessionId: "s-a")
        let b = try makeProfile(home, ".claude-B", sessionId: "s-b")
        let sessions = try await ProfileSessionDiscovery(profiles: [a, b]).discoverSessions()
        #expect(Set(sessions.map(\.id)) == ["s-a", "s-b"])
        #expect(sessions.first { $0.id == "s-a" }?.configDirectory == a.path)
        #expect(sessions.first { $0.id == "s-b" }?.configDirectory == b.path)
    }

    @Test func disabledProfileIsNeverRead() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let a = try makeProfile(home, ".claude", sessionId: "s-a")
        let b = try makeProfile(home, ".claude-B", sessionId: "s-b", enabled: false)
        let sessions = try await ProfileSessionDiscovery(profiles: [a, b]).discoverSessions()
        #expect(sessions.map(\.id) == ["s-a"])
    }

    @Test func disablingDropsItsSessions() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let a = try makeProfile(home, ".claude", sessionId: "s-a")
        var b = try makeProfile(home, ".claude-B", sessionId: "s-b")
        let discovery = ProfileSessionDiscovery(profiles: [a, b])
        #expect(try await discovery.discoverSessions().count == 2)
        b.enabled = false
        discovery.setProfiles([a, b])
        #expect(try await discovery.discoverSessions().map(\.id) == ["s-a"])
        b.enabled = true
        discovery.setProfiles([a, b])
        #expect(try await discovery.discoverSessions().count == 2)
    }

    @Test func missingFolderIsSkipped() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let a = try makeProfile(home, ".claude", sessionId: "s-a")
        let gone = ClaudeProfile(path: home + "/.claude-gone", enabled: true, home: home)
        let sessions = try await ProfileSessionDiscovery(profiles: [a, gone]).discoverSessions()
        #expect(sessions.map(\.id) == ["s-a"])
    }

    @Test func sameIdNewestWins() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let a = try makeProfile(home, ".claude", sessionId: "dup", modified: .now.addingTimeInterval(-3600))
        let b = try makeProfile(home, ".claude-B", sessionId: "dup", modified: .now)
        let sessions = try await ProfileSessionDiscovery(profiles: [a, b]).discoverSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].configDirectory == b.path)
    }

    @Test func onlyDefaultBehavesAsBefore() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let a = try makeProfile(home, ".claude", sessionId: "s-a")
        let direct = try await ClaudeCodeSessionDiscovery(claudeDir: a.projectsDirectory).discoverSessions()
        let viaProfiles = try await ProfileSessionDiscovery(profiles: [a]).discoverSessions()
        #expect(viaProfiles.map(\.id) == direct.map(\.id))
        #expect(viaProfiles.map(\.jsonlPath) == direct.map(\.jsonlPath))
    }

    @Test func neverReadsAProfileThatIsTheHomeFolder() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        // `<home>/projects/<folder>/<id>.jsonl` would be a transcript of a profile at home.
        let atHome = try makeProfile(home, "", sessionId: "s-home")
        let ok = try makeProfile(home, ".claude-B", sessionId: "s-b")
        let sessions = try await ProfileSessionDiscovery(profiles: [atHome, ok], home: home).discoverSessions()
        #expect(sessions.map(\.id) == ["s-b"])
    }
}
