import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ProfileWrites")
struct ProfileWritesTests {
    private func makeHome() throws -> String {
        let dir = NSTemporaryDirectory() + "kanban-code-writes-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A transcript `<home>/<profile>/projects/-x/<id>.jsonl` with two lines.
    private func makeTranscript(home: String, profile: String, id: String) throws -> String {
        let dir = home + "/" + profile + "/projects/-x"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/\(id).jsonl"
        try [
            #"{"type":"user","sessionId":"\#(id)","message":{"content":"Hello"},"cwd":"/x"}"#,
            #"{"type":"assistant","sessionId":"\#(id)","message":{"content":[{"type":"text","text":"Hi"}]}}"#,
        ].joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test func moveStaysInSourceProfile() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let from = try makeTranscript(home: home, profile: ".claude-A", id: "id1")
        // A project that exists nowhere else, so a stray write is easy to see.
        let target = "/kc-test-\(UUID().uuidString.prefix(8))"
        let strayDefault = NSHomeDirectory() + "/.claude/projects/" + SessionFileMover.encodeProjectPath(target)
        defer { try? FileManager.default.removeItem(atPath: strayDefault) }

        let moved = try SessionFileMover.moveSession(sessionId: "id1", fromPath: from, toProjectPath: target)

        #expect(moved == home + "/.claude-A/projects/" + SessionFileMover.encodeProjectPath(target) + "/id1.jsonl")
        #expect(FileManager.default.fileExists(atPath: moved))
        #expect(!FileManager.default.fileExists(atPath: from))
        #expect(!FileManager.default.fileExists(atPath: strayDefault))
    }

    @Test func moveFromDefaultUnchanged() {
        #expect(ClaudeProfile.projectsDirectory(ofTranscript: "/h/.claude/projects/-a/i.jsonl") == "/h/.claude/projects")
        // Outside the profile layout the old fallback applies.
        #expect(ClaudeProfile.projectsDirectory(ofTranscript: "/tmp/i.jsonl") == nil)
    }

    @Test func forkStaysInSourceProfile() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let from = try makeTranscript(home: home, profile: ".claude-A", id: "id2")
        let newId = try await ClaudeCodeSessionStore().forkSession(sessionPath: from, targetDirectory: nil)
        #expect(FileManager.default.fileExists(atPath: home + "/.claude-A/projects/-x/\(newId).jsonl"))
    }

    @Test func summaryUpdateTouchesOnlyItsProfile() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        func writeIndex(_ profile: String) throws -> String {
            let dir = home + "/" + profile + "/projects/-x"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let path = dir + "/sessions-index.json"
            try #"{"version":1,"entries":[{"sessionId":"same","summary":"old"}]}"#
                .write(toFile: path, atomically: true, encoding: .utf8)
            return path
        }
        let indexA = try writeIndex(".claude-A")
        let indexB = try writeIndex(".claude-B")
        try SessionIndexReader.updateSummary(
            sessionId: "same", summary: "new", claudeDir: home + "/.claude-A/projects")
        #expect(try String(contentsOfFile: indexA, encoding: .utf8).contains("new"))
        #expect(try String(contentsOfFile: indexB, encoding: .utf8).contains("old"))
    }

    @Test func writeSessionUsesGivenDirectory() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let store = ClaudeCodeSessionStore(claudeDir: home + "/.claude-A/projects")
        let path = try await store.writeSession(turns: [], sessionId: "w1", projectPath: "/p")
        #expect(path.hasPrefix(home + "/.claude-A/projects/"))
    }
}
