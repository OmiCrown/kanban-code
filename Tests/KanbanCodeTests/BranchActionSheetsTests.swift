import Foundation
import KanbanCodeCore
import Testing

@testable import KanbanCode

@Suite("Merge into main sheet text")
struct BranchActionSheetsTests {

    private static func commits(_ n: Int) -> [CommitLine] {
        (1...n).map { CommitLine(sha: String(format: "%040x", $0), subject: "subject \($0)") }
    }

    private static func preflight(
        _ relation: BranchRelation,
        mainBranch: String? = "main",
        mainDirty: [String] = [],
        worktreeDirty: [String] = [],
        docs: [DocCandidate] = []
    ) -> MergePreflight {
        MergePreflight(
            mainCheckout: "/repo",
            mainBranch: mainBranch,
            branch: "feat/x",
            worktreePath: "/repo.worktrees/x",
            relation: relation,
            mainDirtyPaths: mainDirty,
            worktreeDirtyPaths: worktreeDirty,
            docs: docs
        )
    }

    // MARK: - Commits

    @Test("a fast-forward lists the commits that go into main, oldest first")
    func fastForwardLists() {
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(2))))
        #expect(lines.contains("2 commits go into main"))
        #expect(lines.contains { $0.contains("subject 1") })
        #expect(lines.contains { $0.contains("subject 2") })
        let first = lines.firstIndex { $0.contains("subject 1") }
        let second = lines.firstIndex { $0.contains("subject 2") }
        #expect(first != nil && second != nil && first! < second!)
    }

    @Test("one commit reads in the singular")
    func singular() {
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(1))))
        #expect(lines.contains("1 commit goes into main"))
    }

    @Test("the merge line names master when the main checkout is on master")
    func namesMaster() {
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(2)), mainBranch: "master"))
        #expect(lines.contains("2 commits go into master"))
    }

    @Test("more than 20 commits are cut off with an 'and N more' line")
    func cappedCommits() {
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(25))))
        #expect(lines.contains("25 commits go into main"))
        #expect(lines.contains { $0.contains("subject 20") })
        #expect(!lines.contains { $0.contains("subject 21") })
        #expect(lines.contains("and 5 more"))
    }

    @Test("exactly 20 commits are all listed, with no 'and N more' line")
    func twentyCommits() {
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(20))))
        #expect(lines.contains { $0.contains("subject 20") })
        #expect(!lines.contains { $0.hasPrefix("and ") })
    }

    @Test("an up-to-date branch says it is already in main")
    func upToDate() {
        let lines = MergeSheetText.lines(for: Self.preflight(.upToDate))
        #expect(lines.contains("feat/x is already in main"))
    }

    // MARK: - Diverged

    @Test("a diverged branch shows both commit lists and offers no merge")
    func diverged() {
        let ahead = [CommitLine(sha: "aaaaaaa1111", subject: "on the branch")]
        let behind = [CommitLine(sha: "bbbbbbb2222", subject: "only in main"), CommitLine(sha: "ccccccc3333", subject: "also only in main")]
        let lines = MergeSheetText.lines(for: Self.preflight(.diverged(ahead: ahead, behind: behind)))
        #expect(lines.contains { $0.contains("on the branch") })
        #expect(lines.contains { $0.contains("only in main") })
        #expect(lines.contains { $0.contains("also only in main") })
        #expect(lines.contains { $0.contains("diverged") })
        #expect(!lines.contains { $0.contains("go into") || $0.contains("goes into") })
    }

    // MARK: - Main on another branch

    @Test("main on another branch names that branch")
    func mainNotOnMain() {
        let lines = MergeSheetText.lines(for: Self.preflight(.mainNotOnMain(current: "release/1.2"), mainBranch: nil))
        #expect(lines.contains { $0.contains("release/1.2") })
        #expect(!lines.contains { $0.contains("go into") })
    }

    @Test("main on a detached HEAD says so")
    func mainDetached() {
        let lines = MergeSheetText.lines(for: Self.preflight(.mainNotOnMain(current: nil), mainBranch: nil))
        #expect(lines.contains { $0.contains("detached HEAD") })
    }

    // MARK: - Dirty paths

    @Test("uncommitted paths in main are a warning that lists the paths")
    func dirtyMain() {
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(1)), mainDirty: ["a.swift", "b.swift"]))
        let warning = lines.first { $0.hasPrefix("Warning") }
        #expect(warning != nil)
        #expect(warning?.contains("2") == true)
        #expect(lines.contains { $0.contains("a.swift") })
        #expect(lines.contains { $0.contains("b.swift") })
    }

    @Test("a long list of dirty paths in main is cut off at 20 with 'and N more'")
    func dirtyMainCapped() {
        let paths = (1...23).map { "file\($0).txt" }
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(1)), mainDirty: paths))
        #expect(lines.contains { $0.contains("file20.txt") })
        #expect(!lines.contains { $0.contains("file21.txt") })
        #expect(lines.contains("and 3 more"))
    }

    @Test("a clean main has no warning")
    func cleanMain() {
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(1))))
        #expect(!lines.contains { $0.hasPrefix("Warning") })
    }

    @Test("uncommitted paths in the worktree are said not to travel")
    func dirtyWorktree() {
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(1)), worktreeDirty: ["wip.swift"]))
        #expect(lines.contains { $0.contains("worktree") && $0.contains("not") })
        #expect(lines.contains { $0.contains("wip.swift") })
    }

    // MARK: - Docs

    @Test("a doc that differs in main is named")
    func differentDoc() {
        let docs = [DocCandidate(path: "docs/plan.md", state: .different)]
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(1)), docs: docs))
        #expect(lines.contains { $0.contains("docs/plan.md") })
    }

    @Test("new and identical docs are not listed as text: the sheet shows a checkbox for new ones")
    func newDocsNotListed() {
        let docs = [DocCandidate(path: "docs/new.md", state: .new), DocCandidate(path: "docs/same.md", state: .identical)]
        let lines = MergeSheetText.lines(for: Self.preflight(.fastForward(commits: Self.commits(1)), docs: docs))
        #expect(!lines.contains { $0.contains("docs/new.md") })
        #expect(!lines.contains { $0.contains("docs/same.md") })
    }

    // MARK: - Result notices

    @Test("a merge notice names the old and new heads and the carried docs")
    func mergedNotice() {
        let text = MergeSheetText.resultNotice(.merged(
            oldHead: "1111111aaaaaaaa", newHead: "2222222bbbbbbbb", copied: ["docs/a.md", "docs/b.md"], skipped: []
        ))
        #expect(text.contains("1111111"))
        #expect(text.contains("2222222"))
        #expect(!text.contains("1111111a"))
        #expect(text.contains("2 files copied"))
        #expect(!text.contains("not copied"))
    }

    @Test("skipped files are worded neutrally, not as identical")
    func skippedNotice() {
        let text = MergeSheetText.resultNotice(.merged(oldHead: "1111111", newHead: "2222222", copied: [], skipped: ["docs/x.md"]))
        #expect(text.contains("1 file not copied: already identical in main, or could not be copied; see the log"))
    }

    @Test("an already-in-main notice says nothing was merged")
    func alreadyInMainNotice() {
        let text = MergeSheetText.resultNotice(.alreadyInMain(copied: ["docs/a.md"], skipped: []))
        #expect(text.contains("already in main"))
        #expect(text.contains("1 file copied"))
    }

    @Test("a refusal shows its own text")
    func refusedNotice() {
        #expect(MergeSheetText.resultNotice(.refused("feat/x cannot be fast-forwarded.")) == "feat/x cannot be fast-forwarded.")
    }
}
