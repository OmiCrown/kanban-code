import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("BuildInfo")
struct BuildInfoTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let fullSHA = "2dfdd6fa957cd54942b78bbbf8f7043c00d821b6"

    private func stamped(dirty: String = "true", worktree: String = "about-build-info") -> [String: Any] {
        [
            "KCGitDescribe": "v0.1.32-444-g2dfdd6f",
            "KCGitBranch": "feat/x",
            "KCGitSHA": fullSHA,
            "KCGitDirty": dirty,
            "KCBuildDate": "2026-11-22T01:30:00Z",
            "KCSourceRepo": "/r",
            "KCWorktree": worktree,
        ]
    }

    @Test func parsesStampedKeys() throws {
        let info = try #require(BuildInfo(infoDictionary: stamped()))
        #expect(info.describe == "v0.1.32-444-g2dfdd6f")
        #expect(info.branch == "feat/x")
        #expect(info.sha == fullSHA)
        #expect(info.dirty)
        #expect(info.sourceRepo == "/r")
        #expect(info.worktree == "about-build-info")
        #expect(info.shortSHA == "2dfdd6f")
        #expect(info.commitText == "2dfdd6f (dirty)")
        #expect(info.buildDateText(in: utc) == "2026-11-22 01:30 GMT")
    }

    @Test func cleanBuildHasNoDirtyBadge() throws {
        let info = try #require(BuildInfo(infoDictionary: stamped(dirty: "false")))
        #expect(info.dirty == false)
        #expect(info.commitText == "2dfdd6f")
    }

    @Test func mainCheckoutHasNoWorktree() throws {
        let info = try #require(BuildInfo(infoDictionary: stamped(worktree: "")))
        #expect(info.worktree == nil)
    }

    @Test func noKeysMeansNoInfo() {
        #expect(BuildInfo(infoDictionary: ["CFBundleName": "Kanban Code"]) == nil)
        #expect(BuildInfo(infoDictionary: nil) == nil)
    }

    @Test func partialKeysDoNotCrash() throws {
        let info = try #require(BuildInfo(infoDictionary: ["KCBuildDate": "2026-11-22T01:30:00Z"]))
        #expect(info.commitText == nil)
        #expect(info.branch == nil)
        let summary = info.summaryText(freshness: nil, timeZone: utc)
        #expect(summary.contains("Built:"))
        #expect(!summary.contains("Branch:"))

        let garbage = try #require(BuildInfo(infoDictionary: ["KCBuildDate": "yesterday", "KCGitBranch": "main"]))
        #expect(garbage.buildDate == nil)
        #expect(garbage.buildDateText(in: utc) == nil)
    }

    @Test func freshnessCanBeCheckedOnlyWithSourcesAndCommit() throws {
        let full = try #require(BuildInfo(infoDictionary: stamped()))
        #expect(full.canCheckFreshness)

        // A CI-built release carries a commit but no source path: there is nothing local to compare with.
        var released = stamped()
        released["KCSourceRepo"] = nil
        #expect(try #require(BuildInfo(infoDictionary: released)).canCheckFreshness == false)

        #expect(BuildInfo(sourceRepo: "/r").canCheckFreshness == false)
    }

    @Test func summaryListsRowsInOrder() throws {
        let info = try #require(BuildInfo(infoDictionary: stamped()))
        let lines = info.summaryText(freshness: .unknown, timeZone: utc).split(separator: "\n").map(String.init)
        let prefixes = ["Version:", "Branch:", "Worktree:", "Commit:", "Built:", "Sources:"]
        #expect(lines.count == prefixes.count)
        for (line, prefix) in zip(lines, prefixes) { #expect(line.hasPrefix(prefix)) }

        let main = try #require(BuildInfo(infoDictionary: stamped(worktree: "")))
        #expect(!main.summaryText(freshness: .unknown, timeZone: utc).contains("Worktree:"))
        #expect(!info.summaryText(freshness: nil, timeZone: utc).contains("Sources:"))
    }
}
