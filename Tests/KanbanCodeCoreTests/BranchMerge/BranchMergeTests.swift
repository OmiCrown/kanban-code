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

    // MARK: - Docs

    @Test func newDocIsCandidate() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try fx.write("docs/superpowers/specs/a.md", in: wt, "spec\n")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs == [DocCandidate(path: "docs/superpowers/specs/a.md", state: .new)])
        #expect(result.blockReason == nil)
    }

    @Test func identicalDocIsMarkedIdentical() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try fx.write("docs/a.md", in: wt, "same\n")
        try fx.write("docs/a.md", in: fx.repo, "same\n")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs == [DocCandidate(path: "docs/a.md", state: .identical)])
        #expect(result.blockReason == nil)
    }

    @Test func differentDocBlocks() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try fx.write("docs/a.md", in: wt, "worktree version\n")
        try fx.write("docs/a.md", in: fx.repo, "main version\n")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs == [DocCandidate(path: "docs/a.md", state: .different)])
        #expect(result.blockReason?.contains("docs/a.md") == true)
    }

    @Test func committedDocIsNotCandidate() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "docs/committed.md", content: "c\n")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs.isEmpty)
    }

    @Test func ignoredSuperpowersNeverListed() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try fx.write(".superpowers/sdd/ledger.md", in: wt, "ledger\n")
        try fx.write("docs/.superpowers/x.md", in: wt, "nested\n")  // the exclude pattern matches at any depth
        try fx.write("docs/kept.md", in: wt, "kept\n")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs.map(\.path) == ["docs/kept.md"])
    }

    @Test func nonDocsUntrackedNeverListed() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try fx.write("notes.txt", in: wt, "n")
        try fx.write("build-app.log", in: wt, "log")
        try fx.write("src/docs/x.md", in: wt, "x")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs.isEmpty)
        #expect(Set(result.worktreeDirtyPaths).isSuperset(of: ["notes.txt", "build-app.log"]))
    }

    @Test func docNameWithSpacesAndUnicode() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try fx.write("docs/plans/план 1.md", in: wt, "п\n")
        try fx.write("docs/b c.md", in: wt, "b\n")

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs.map(\.path) == ["docs/b c.md", "docs/plans/план 1.md"])
        #expect(result.docs.allSatisfy { $0.state == .new })
    }

    @Test func symlinkAndDirectoryUnderDocsSkipped() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        try fx.write("docs/real.md", in: wt, "real\n")
        try FileManager.default.createSymbolicLink(atPath: wt + "/docs/link.md", withDestinationPath: "real.md")
        try FileManager.default.createSymbolicLink(atPath: wt + "/docs/dirlink", withDestinationPath: fx.root)
        try FileManager.default.createDirectory(atPath: wt + "/docs/emptydir", withIntermediateDirectories: true)

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs.map(\.path) == ["docs/real.md"])
    }

    @Test func docsAreSortedByPath() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        for name in ["docs/z.md", "docs/a/b.md", "docs/a.md"] { try fx.write(name, in: wt, name) }

        let result = try await BranchMerge().preflight(worktreePath: wt, branch: "feat-a")

        #expect(result.docs.map(\.path) == result.docs.map(\.path).sorted())
        #expect(result.docs.count == 3)
    }

    // MARK: - Status safety

    @Test func statusNeverTakesOptionalLocks() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        let recorder = ArgsRecorder()
        let merge = BranchMerge(run: { args, cwd in
            recorder.record(args)
            return await GitRepoSync.shell(args, cwd)
        })

        _ = try await merge.preflight(worktreePath: wt, branch: "feat-a")

        let statuses = recorder.calls.filter { $0.contains("status") }
        #expect(statuses.count == 2)  // main checkout and worktree
        for call in statuses {
            let optional = call.firstIndex(of: "--no-optional-locks")
            let status = call.firstIndex(of: "status")
            #expect(optional != nil && status != nil && optional! < status!, "\(call)")
        }
    }

    @Test func failingStatusInMainThrowsInsteadOfLookingClean() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        let merge = BranchMerge(run: { args, cwd in
            if args.contains("status"), cwd == fx.repo {
                return ShellCommand.Result(exitCode: 128, stdout: "", stderr: "fatal: unable to read index\n")
            }
            return await GitRepoSync.shell(args, cwd)
        })

        do {
            _ = try await merge.preflight(worktreePath: wt, branch: "feat-a")
            Issue.record("expected a refusal")
        } catch let error as BranchMergeError {
            guard case .refused(let text) = error else { return }
            #expect(text.contains("unable to read index"))
        }
    }

    @Test func failingStatusInWorktreeThrowsInsteadOfLookingClean() async throws {
        let fx = try await GitFixture.make()
        defer { fx.cleanup() }
        let wt = try await fx.addWorktree("a", branch: "feat-a", sibling: true)
        try await fx.commit(in: wt, file: "a.txt", content: "a")
        let merge = BranchMerge(run: { args, cwd in
            if args.contains("status"), cwd == wt {
                return ShellCommand.Result(exitCode: 128, stdout: "", stderr: "fatal: not a git repository\n")
            }
            return await GitRepoSync.shell(args, cwd)
        })

        do {
            _ = try await merge.preflight(worktreePath: wt, branch: "feat-a")
            Issue.record("expected a refusal")
        } catch let error as BranchMergeError {
            guard case .refused(let text) = error else { return }
            #expect(text.contains("not a git repository"))
        }
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

/// Records the arguments of every git call a test runner sees.
private final class ArgsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[String]] = []

    func record(_ args: [String]) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(args)
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
