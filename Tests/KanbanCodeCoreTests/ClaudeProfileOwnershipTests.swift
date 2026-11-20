import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ClaudeProfileOwnership")
struct ClaudeProfileOwnershipTests {
    @Test func claudeOwnsDotClaudeDash() {
        let path = "/Users/x/.claude-Client/projects/a/b.jsonl"
        #expect(CodingAssistant.claude.owns(sessionPath: path))
        #expect(!CodingAssistant.codex.owns(sessionPath: path))
        #expect(!CodingAssistant.gemini.owns(sessionPath: path))
    }

    @Test func claudeOwnsDefault() {
        #expect(CodingAssistant.claude.owns(sessionPath: "/Users/x/.claude/projects/a/b.jsonl"))
    }

    @Test func lookalikeNotOwned() {
        #expect(!CodingAssistant.claude.owns(sessionPath: "/Users/x/.claudette/a.jsonl"))
        #expect(!CodingAssistant.claude.owns(sessionPath: "/Users/x/claude-foo/a.jsonl"))
    }

    @Test func ownerOfSessionPath() {
        #expect(CodingAssistant.owner(ofSessionPath: "/Users/x/.claude-Work/projects/a/b.jsonl") == .claude)
        #expect(CodingAssistant.owner(ofSessionPath: "/Users/x/.codex/sessions/a.jsonl") == .codex)
        #expect(CodingAssistant.owner(ofSessionPath: "/tmp/fixture/a.jsonl") == nil)
    }

    @Test func profileTranscriptIsNotOwnedByOther() {
        #expect(!CodingAssistant.claude.ownedByOther(sessionPath: "/Users/x/.claude-Work/projects/a/b.jsonl"))
        #expect(CodingAssistant.codex.ownedByOther(sessionPath: "/Users/x/.claude-Work/projects/a/b.jsonl"))
    }

    @Test func sessionConfigDirectory() {
        let s = Session(id: "b", jsonlPath: "/Users/x/.claude-Omicrown/projects/-p/b.jsonl")
        #expect(s.configDirectory == "/Users/x/.claude-Omicrown")
        #expect(Session(id: "c").configDirectory == nil)
        #expect(Session(id: "d", jsonlPath: "/tmp/d.jsonl").configDirectory == nil)
    }
}
