import Foundation
import Testing

@testable import KanbanCodeCore

@Suite("Branch finish", .serialized)
struct BranchFinishTests {
    // MARK: - state

    @Test func branchMergedIsAncestorCheck() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "one.txt", content: "1")

        let before = try await BranchFinish().state(worktreePath: wt, branch: "feat-a")
        #expect(before.branchMerged == false)
        #expect(before.mainCheckout == fx.repo)

        try await fx.git(["merge", "--ff-only", "feat-a"], in: fx.repo)
        let after = try await BranchFinish().state(worktreePath: wt, branch: "feat-a")
        #expect(after.branchMerged == true)
    }

    @Test func branchMergedAlsoWhenMainMovedPast() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "one.txt", content: "1")
        try await fx.git(["merge", "--ff-only", "feat-a"], in: fx.repo)
        try await fx.commit(in: fx.repo, file: "later.txt", content: "2")

        let state = try await BranchFinish().state(worktreePath: wt, branch: "feat-a")
        #expect(state.branchMerged == true)
    }

    @Test func stateThrowsWhenMainCheckoutNotOnMain() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.git(["checkout", "-q", "-b", "other"], in: fx.repo)

        await #expect(throws: BranchMergeError.self) {
            _ = try await BranchFinish().state(worktreePath: wt, branch: "feat-a")
        }
    }

    @Test func stateThrowsWhenBranchDoesNotExist() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)

        await #expect(throws: BranchMergeError.self) {
            _ = try await BranchFinish().state(worktreePath: wt, branch: "no-such-branch")
        }
    }

    @Test func ignoredFolderCounted() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try fx.write(".superpowers/one.md", in: wt, "1")
        try fx.write(".superpowers/sub/two.md", in: wt, "2")
        try fx.write(".superpowers/sub/three.md", in: wt, "3")

        let state = try await BranchFinish().state(worktreePath: wt, branch: "feat-a")

        #expect(state.ignored == [IgnoredEntry(path: ".superpowers/", fileCount: 3)])
    }

    @Test func ignoredFileCountsOneAndEntriesAreSorted() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        try fx.write(".gitignore", in: fx.repo, "*.log\nbuild/\n")
        try await fx.git(["add", ".gitignore"], in: fx.repo)
        try await fx.git(["commit", "-q", "-m", "ignore"], in: fx.repo)
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try fx.write("z.log", in: wt, "z")
        try fx.write("build/x.o", in: wt, "x")
        try fx.write(".superpowers/a.md", in: wt, "a")

        let state = try await BranchFinish().state(worktreePath: wt, branch: "feat-a")

        #expect(state.ignored == [
            IgnoredEntry(path: ".superpowers/", fileCount: 1),
            IgnoredEntry(path: "build/", fileCount: 1),
            IgnoredEntry(path: "z.log", fileCount: 1),
        ])
    }

    @Test func ignoredCountDoesNotFollowSymlinks() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try fx.write("elsewhere/1", in: fx.root, "1")
        try fx.write("elsewhere/2", in: fx.root, "2")
        try fx.write("elsewhere/3", in: fx.root, "3")
        try fx.write(".superpowers/real.md", in: wt, "r")
        try FileManager.default.createSymbolicLink(
            atPath: wt + "/.superpowers/link", withDestinationPath: fx.root + "/elsewhere")

        let state = try await BranchFinish().state(worktreePath: wt, branch: "feat-a")

        #expect(state.ignored == [IgnoredEntry(path: ".superpowers/", fileCount: 2)])
    }

    @Test func modifiedAndUntrackedFilesAreNotIgnoredEntries() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try fx.write("untracked.txt", in: wt, "u")
        try fx.write("README.md", in: wt, "changed\n")

        let state = try await BranchFinish().state(worktreePath: wt, branch: "feat-a")

        #expect(state.ignored.isEmpty)
    }

    // MARK: - guard

    private func reason(
        merged: Bool = true, worktree: String = "/x/wt", app: String = "/Applications/Kanban Code.app",
        session: Bool = false, others: Int = 0
    ) -> String? {
        WorktreeRemovalGuard.blockReason(
            branchMerged: merged, worktreePath: worktree, appBundlePath: app,
            hasLiveSession: session, otherActiveCardsOnBranch: others)
    }

    @Test func guardAllowsWhenAllClear() {
        #expect(reason() == nil)
    }

    @Test func guardBlocksWhenNotMerged() {
        let text = reason(merged: false)
        #expect(text?.contains("not merged") == true)
    }

    @Test func guardBlocksWhenAppRunsFromWorktree() {
        let text = reason(app: "/x/wt/.build/Kanban Code.app")
        #expect(text?.contains("running from this worktree") == true)
        #expect(reason(app: "/x/wt")?.contains("running from this worktree") == true)
        #expect(reason(app: "/x/wt/")?.contains("running from this worktree") == true)
    }

    @Test func guardComparesOnPathBoundaries() {
        #expect(reason(app: "/x/wt-2/Kanban Code.app") == nil)
        #expect(reason(app: "") == nil)
    }

    @Test func guardResolvesSymlinks() throws {
        let base = BranchMerge.canonical(NSTemporaryDirectory()) + "/finish-guard-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: base) }
        try FileManager.default.createDirectory(atPath: base + "/wt/app", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: base + "/alias", withDestinationPath: base + "/wt")

        // The app path goes through a symlink to the worktree.
        #expect(reason(worktree: base + "/wt", app: base + "/alias/app")?.contains("running from this worktree") == true)
        // The worktree path is the symlink.
        #expect(reason(worktree: base + "/alias", app: base + "/wt/app")?.contains("running from this worktree") == true)
    }

    @Test func guardBlocksWhenSessionLive() {
        #expect(reason(session: true)?.contains("tmux session") == true)
    }

    @Test func guardBlocksWhenOtherCardUsesBranch() {
        #expect(reason(others: 1)?.contains("Another active card") == true)
        #expect(reason(others: 3)?.contains("3 other active cards") == true)
    }

    @Test func guardCheckOrder() {
        #expect(reason(merged: false, app: "/x/wt/a.app", session: true, others: 2)?.contains("not merged") == true)
        #expect(reason(app: "/x/wt/a.app", session: true, others: 2)?.contains("running from") == true)
        #expect(reason(session: true, others: 2)?.contains("tmux") == true)
    }

    // MARK: - removeWorktree

    @Test func removeWorktreeRemovesAndPrunes() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)

        let result = await BranchFinish().removeWorktree(mainCheckout: fx.repo, worktreePath: wt)

        #expect(result.isSuccess)
        #expect(!FileManager.default.fileExists(atPath: wt))
        let list = try await fx.git(["worktree", "list", "--porcelain"], in: fx.repo)
        #expect(list.components(separatedBy: "\n").filter { $0.hasPrefix("worktree ") }.count == 1)
    }

    @Test func removeRefusesWithUntrackedFile() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try fx.write("notes.txt", in: wt, "keep me")

        let result = await BranchFinish().removeWorktree(mainCheckout: fx.repo, worktreePath: wt)

        guard case .failure(.refused(let text)) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(!text.isEmpty)
        #expect(FileManager.default.fileExists(atPath: wt + "/notes.txt"))
    }

    @Test func removeIgnoresIgnoredFolder() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try fx.write(".superpowers/plan.md", in: wt, "plan")

        let result = await BranchFinish().removeWorktree(mainCheckout: fx.repo, worktreePath: wt)

        #expect(result.isSuccess)
        #expect(!FileManager.default.fileExists(atPath: wt))
    }

    @Test func removeFailureCarriesGitText() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }

        let result = await BranchFinish().removeWorktree(mainCheckout: fx.repo, worktreePath: fx.root + "/nowhere")

        guard case .failure(.refused(let text)) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(text.contains("nowhere"))
    }

    // MARK: - rebuild

    @Test func hasAppTargetReadsMakefile() throws {
        let dir = BranchMerge.canonical(NSTemporaryDirectory()) + "/finish-make-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let finish = BranchFinish()

        #expect(finish.hasAppTarget(mainCheckout: dir) == false)  // no Makefile

        try "build:\n\tswift build\napp: build cli\n\t./bundle.sh\n".write(toFile: dir + "/Makefile", atomically: true, encoding: .utf8)
        #expect(finish.hasAppTarget(mainCheckout: dir) == true)

        try "build:\n\tswift build\n".write(toFile: dir + "/Makefile", atomically: true, encoding: .utf8)
        #expect(finish.hasAppTarget(mainCheckout: dir) == false)
    }

    @Test func hasAppTargetIgnoresSimilarNames() throws {
        let dir = BranchMerge.canonical(NSTemporaryDirectory()) + "/finish-make-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let text = "app-debug:\n\ttrue\napplication:\n\ttrue\n\tapp: not a target\n#app:\napp := 1\napp:=2\n"
        try text.write(toFile: dir + "/Makefile", atomically: true, encoding: .utf8)

        #expect(BranchFinish().hasAppTarget(mainCheckout: dir) == false)
    }

    @Test func rebuildOutputTailKeepsLast40Lines() {
        let out = (1...30).map { "out \($0)" }.joined(separator: "\n")
        let err = (1...30).map { "err \($0)" }.joined(separator: "\n")

        let tail = BranchFinish.outputTail(stdout: out, stderr: err)
        let lines = tail.components(separatedBy: "\n")

        #expect(lines.count == 40)
        #expect(lines.first == "out 21")
        #expect(lines.last == "err 30")
        #expect(BranchFinish.outputTail(stdout: "a\nb", stderr: "") == "a\nb")
        #expect(BranchFinish.outputTail(stdout: "", stderr: "") == "")
    }

    @Test func rebuildEnvironmentSetsDeveloperDirOnlyWhenXcodeInstalled() {
        let base = ["PATH": "/usr/bin", "DEVELOPER_DIR": "/elsewhere"]

        let with = BranchFinish.rebuildEnvironment(base: base, xcodeInstalled: true)
        #expect(with["DEVELOPER_DIR"] == "/Applications/Xcode-26.6.0.app/Contents/Developer")
        #expect(with["PATH"] == "/usr/bin")

        let without = BranchFinish.rebuildEnvironment(base: base, xcodeInstalled: false)
        #expect(without == base)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
