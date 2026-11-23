import Foundation
import Testing

@testable import KanbanCodeCore

@Suite("Branch merge eligibility")
struct BranchMergeEligibilityTests {
    private static func link(
        project: String? = "/repo",
        worktree: String? = "/repo.worktrees/a",
        isRemote: Bool = false,
        remote: RemoteLink? = nil
    ) -> Link {
        Link(
            id: "card-a",
            projectPath: project,
            worktreeLink: worktree.map { WorktreeLink(path: $0, branch: "feat/a") },
            isRemote: isRemote,
            remote: remote
        )
    }

    @Test func offeredForLocalWorktreeInFlagProject() {
        #expect(BranchMergeEligibility.offered(for: Self.link(), mergesWithoutPR: true))
    }

    @Test func hiddenWithoutFlag() {
        #expect(!BranchMergeEligibility.offered(for: Self.link(), mergesWithoutPR: false))
    }

    @Test func hiddenWithoutWorktree() {
        #expect(!BranchMergeEligibility.offered(for: Self.link(worktree: nil), mergesWithoutPR: true))
        #expect(!BranchMergeEligibility.offered(for: Self.link(worktree: ""), mergesWithoutPR: true))
    }

    @Test func hiddenWhenWorktreeIsProjectPath() {
        #expect(!BranchMergeEligibility.offered(for: Self.link(worktree: "/repo"), mergesWithoutPR: true))
        // The same directory spelled differently is still the main checkout.
        #expect(!BranchMergeEligibility.offered(for: Self.link(worktree: "/repo/"), mergesWithoutPR: true))
        #expect(!BranchMergeEligibility.offered(for: Self.link(worktree: "/repo/sub/.."), mergesWithoutPR: true))
    }

    @Test func hiddenForRemoteAndBoxd() {
        #expect(!BranchMergeEligibility.offered(for: Self.link(isRemote: true), mergesWithoutPR: true))
        let boxd = RemoteLink(mode: .boxd, machineName: "kanban-box")
        #expect(!BranchMergeEligibility.offered(for: Self.link(remote: boxd), mergesWithoutPR: true))
    }
}
