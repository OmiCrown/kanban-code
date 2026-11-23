import Foundation
import Testing

@testable import KanbanCodeCore

@Suite("Branch merge preflight", .serialized)
struct BranchMergeTests {
    @Test func fastForwardListsCommits() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "one.txt", content: "1")
        try await fx.commit(in: wt, file: "two.txt", content: "2")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        guard case .fastForward(let commits) = result.relation else {
            Issue.record("expected fastForward, got \(result.relation)")
            return
        }
        #expect(commits.map(\.subject) == ["add one.txt", "add two.txt"])
        #expect(commits.allSatisfy { !$0.sha.isEmpty })
        #expect(result.mainBranch == "main")
        #expect(result.branch == "feat-a")
        #expect(result.worktreePath == wt)
        #expect(result.blockReason == nil)
    }

    @Test func upToDateWhenBranchInMain() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.relation == .upToDate)
        #expect(result.blockReason != nil)
    }

    @Test func upToDateWhenMainMovedPastBranch() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: fx.repo, file: "m.txt", content: "m")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.relation == .upToDate)
    }

    @Test func divergedShowsBothSides() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try await fx.commit(in: fx.repo, file: "m.txt", content: "m")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        guard case .diverged(let ahead, let behind) = result.relation else {
            Issue.record("expected diverged, got \(result.relation)")
            return
        }
        #expect(ahead.map(\.subject) == ["add a.txt"])
        #expect(behind.map(\.subject) == ["add m.txt"])
        #expect(result.blockReason != nil)
    }

    @Test func mainOnOtherBranchIsReported() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try await fx.git(["checkout", "-q", "-b", "side"], in: fx.repo)

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.relation == .mainNotOnMain(current: "side"))
        #expect(result.mainBranch == nil)
        #expect(result.blockReason != nil)
    }

    @Test func detachedMainIsReported() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.git(["checkout", "-q", "--detach"], in: fx.repo)

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.relation == .mainNotOnMain(current: nil))
        #expect(result.blockReason != nil)
    }

    @Test func mainCheckoutFoundFromSiblingAndClaudeLayouts() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let sibling = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        let claude = try await fx.addWorktree("b", branch: "feat-b", sibling: false)

        let fromSibling = try await BranchMerge().preflight(worktreePath: sibling, branch: "feat-a")
        let fromClaude = try await BranchMerge().preflight(worktreePath: claude, branch: "feat-b")

        #expect(fromSibling.mainCheckout == fx.repo)
        #expect(fromClaude.mainCheckout == fx.repo)
    }

    @Test func slashBranchName() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("x", branch: "feat/x", sibling: true)
        try await fx.commit(in: wt, file: "x.txt", content: "x")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat/x")

        guard case .fastForward(let commits) = result.relation else {
            Issue.record("expected fastForward, got \(result.relation)")
            return
        }
        #expect(commits.count == 1)
    }

    @Test func dirtyMainIsListedNotBlocking() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try fx.write("scratch.txt", in: fx.repo, "wip")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.mainDirtyPaths == ["scratch.txt"])
        #expect(result.blockReason == nil)
    }

    @Test func worktreeUncommittedChangesListed() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try fx.write("a.txt", in: wt, "changed")  // tracked, modified: status " M a.txt"
        try fx.write("new.txt", in: wt, "n")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(Set(result.worktreeDirtyPaths) == ["a.txt", "new.txt"])
        #expect(result.mainDirtyPaths.isEmpty)
    }

    @Test func staleWorktreeThrowsRefusal() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        let other = try await fx.addWorktree("b", branch: "feat-b", sibling: true)

        // Branch does not match the worktree at that path.
        await #expect(throws: BranchMergeError.self) {
            _ = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-b")
        }
        // Path removed from disk.
        try FileManager.default.removeItem(atPath: other)
        await #expect(throws: BranchMergeError.self) {
            _ = try await BranchMerge().preflight(worktreePath: other, branch: "feat-b")
        }
    }
}
