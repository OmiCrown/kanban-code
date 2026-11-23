import Foundation

/// An ignored path in a worktree and how many files removing the worktree would delete with it.
public struct IgnoredEntry: Sendable, Equatable {
    /// Relative to the worktree; a directory ends with `/`.
    public var path: String
    public var fileCount: Int

    public init(path: String, fileCount: Int) {
        self.path = path
        self.fileCount = fileCount
    }
}

/// What the Finish dialog needs to know about a worktree before it is removed.
public struct FinishState: Sendable, Equatable {
    public var mainCheckout: String
    /// The branch is contained in the branch checked out in the main checkout.
    public var branchMerged: Bool
    /// Ignored files and folders that removing the worktree deletes, sorted by path.
    public var ignored: [IgnoredEntry]

    public init(mainCheckout: String, branchMerged: Bool, ignored: [IgnoredEntry]) {
        self.mainCheckout = mainCheckout
        self.branchMerged = branchMerged
        self.ignored = ignored
    }
}

/// The conditions under which a worktree must not be removed.
public enum WorktreeRemovalGuard {
    /// A sentence naming the first thing that blocks removal, or nil when nothing does.
    /// `otherActiveCardsOnBranch` counts the cards other than the one being finished.
    public static func blockReason(
        branchMerged: Bool,
        worktreePath: String,
        appBundlePath: String,
        hasLiveSession: Bool,
        otherActiveCardsOnBranch: Int
    ) -> String? {
        if !branchMerged {
            return "The branch is not merged into main yet, so removing the worktree would lose its commits."
        }
        if isInside(appBundlePath, of: worktreePath) {
            return "Kanban Code is running from this worktree (\(appBundlePath)); removing it would delete the running app."
        }
        if hasLiveSession {
            return "A tmux session is still running for this card; stop it before removing the worktree."
        }
        if otherActiveCardsOnBranch > 0 {
            let cards = otherActiveCardsOnBranch == 1 ? "Another active card uses" : "\(otherActiveCardsOnBranch) other active cards use"
            return "\(cards) this branch; finish or move it first."
        }
        return nil
    }

    /// `path` is `directory` or lies under it, compared on path components after
    /// resolving symlinks (`/x/wt-2` is not inside `/x/wt`).
    static func isInside(_ path: String, of directory: String) -> Bool {
        guard !path.isEmpty, !directory.isEmpty else { return false }
        let inner = normalized(path)
        let outer = normalized(directory)
        return inner == outer || inner.hasPrefix(outer == "/" ? "/" : outer + "/")
    }

    private static func normalized(_ path: String) -> String {
        var resolved = BranchMerge.canonical(path)
        while resolved.count > 1, resolved.hasSuffix("/") { resolved.removeLast() }
        return resolved
    }
}

/// Checks before, and the work after, a worktree branch has been merged into main:
/// remove the worktree and rebuild the app from the main checkout.
public struct BranchFinish: Sendable {
    let run: GitRepoSync.Runner

    public init(run: @escaping GitRepoSync.Runner = GitRepoSync.shell) {
        self.run = run
    }

    private static let log = "merge"
    static let xcodeDeveloperDir = "/Applications/Xcode-26.6.0.app/Contents/Developer"
    static let outputTailLines = 40

    // MARK: - State

    /// Whether `branch` is contained in the main checkout's branch, and what ignored
    /// files the worktree holds. Throws `BranchMergeError.refused` when git cannot say:
    /// an unreadable state must not look clean.
    public func state(worktreePath: String, branch: String) async throws -> FinishState {
        let list = await run(["worktree", "list", "--porcelain"], worktreePath)
        guard list.succeeded else {
            throw BranchMergeError.refused("Cannot list worktrees: \(GitRepoSync.firstLine(list))")
        }
        // The first record of `git worktree list` is always the main checkout.
        guard let main = BranchMerge.parseWorktrees(list.stdout).first else {
            throw BranchMergeError.refused("git reported no worktrees for \(worktreePath).")
        }
        let mainCheckout = main.path
        let head = await run(["symbolic-ref", "--short", "-q", "HEAD"], mainCheckout)
        let mainBranch = head.succeeded ? head.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard mainBranch == "main" || mainBranch == "master" else {
            let described = mainBranch.isEmpty ? "a detached HEAD" : "'\(mainBranch)'"
            throw BranchMergeError.refused("The main checkout is on \(described), not main or master; cannot tell whether \(branch) is merged.")
        }

        let ancestor = await run(["merge-base", "--is-ancestor", "refs/heads/\(branch)", mainBranch], mainCheckout)
        let merged: Bool
        switch ancestor.exitCode {
        case 0: merged = true
        case 1: merged = false
        default:
            throw BranchMergeError.refused("Cannot compare \(branch) with \(mainBranch): \(GitRepoSync.firstLine(ancestor))")
        }

        let status = await run(["--no-optional-locks", "status", "--ignored", "--porcelain=v1", "-z"], worktreePath)
        guard status.succeeded else {
            throw BranchMergeError.refused("Cannot read the git status of \(worktreePath): \(GitRepoSync.firstLine(status))")
        }
        let ignored = Self.ignoredPaths(status.stdout)
            .map { IgnoredEntry(path: $0, fileCount: Self.countFiles(at: worktreePath + "/" + $0)) }
            .sorted { $0.path < $1.path }
        return FinishState(mainCheckout: mainCheckout, branchMerged: merged, ignored: ignored)
    }

    /// The `!!` entries of `status --ignored --porcelain=v1 -z`. A rename or copy is
    /// followed by one extra entry holding the source path, which is skipped.
    static func ignoredPaths(_ output: String) -> [String] {
        let entries = output.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)
        var paths: [String] = []
        var index = 0
        while index < entries.count {
            let entry = entries[index]
            index += 1
            if entry.hasPrefix("!! ") {
                paths.append(String(entry.dropFirst(3)))
            } else if entry.first == "R" || entry.first == "C" {
                index += 1
            }
        }
        return paths
    }

    /// Files under `path` (a file counts 1), without following symlinks: a symlink is one file.
    static func countFiles(at path: String) -> Int {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        var info = stat()
        guard lstat(clean, &info) == 0 else { return 0 }
        guard info.st_mode & S_IFMT == S_IFDIR else { return 1 }
        guard let walker = FileManager.default.enumerator(atPath: clean) else { return 0 }
        var count = 0
        for case let relative as String in walker {
            var child = stat()
            guard lstat(clean + "/" + relative, &child) == 0 else { continue }
            if child.st_mode & S_IFMT != S_IFDIR { count += 1 }
        }
        return count
    }

    // MARK: - Removal

    /// `git worktree remove` without `--force`, then `git worktree prune`, both in the
    /// main checkout. Git refuses a worktree with modified or untracked files; ignored
    /// files do not block it.
    public func removeWorktree(mainCheckout: String, worktreePath: String) async -> Result<Void, BranchMergeError> {
        let removed = await run(["worktree", "remove", worktreePath], mainCheckout)
        guard removed.succeeded else {
            let text = Self.message(removed, fallback: "git worktree remove failed with exit code \(removed.exitCode).")
            KanbanCodeLog.warn(Self.log, "worktree remove refused for \(worktreePath): \(text)")
            return .failure(.refused(text))
        }
        let pruned = await run(["worktree", "prune"], mainCheckout)
        guard pruned.succeeded else {
            let text = Self.message(pruned, fallback: "git worktree prune failed with exit code \(pruned.exitCode).")
            KanbanCodeLog.warn(Self.log, "worktree prune failed after removing \(worktreePath): \(text)")
            return .failure(.refused("The worktree was removed, but git worktree prune failed: \(text)"))
        }
        KanbanCodeLog.info(Self.log, "removed worktree \(worktreePath)")
        return .success(())
    }

    private static func message(_ result: ShellCommand.Result, fallback: String) -> String {
        let text = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }

    // MARK: - Rebuild

    /// True when the main checkout's Makefile has a target named exactly `app`.
    public func hasAppTarget(mainCheckout: String) -> Bool {
        guard let makefile = try? String(contentsOfFile: mainCheckout + "/Makefile", encoding: .utf8) else { return false }
        return makefile.split(whereSeparator: \.isNewline).contains { line in
            guard line.hasPrefix("app:") else { return false }
            return !line.dropFirst("app:".count).hasPrefix("=")  // `app:=` assigns a variable
        }
    }

    /// Runs `make app` in the main checkout. Only builds: the running app is neither
    /// stopped nor reopened (docs/building.md: the restart is a separate manual step).
    public func rebuildApp(mainCheckout: String) async -> (ok: Bool, outputTail: String) {
        let environment = Self.rebuildEnvironment(
            base: ShellCommand.loginEnvironment,
            xcodeInstalled: FileManager.default.fileExists(atPath: Self.xcodeDeveloperDir))
        let make = ShellCommand.findExecutable("make") ?? "/usr/bin/make"
        do {
            let result = try await ShellCommand.run(
                make, arguments: ["app"], currentDirectory: mainCheckout, environment: environment, timeout: 1800)
            KanbanCodeLog.info(Self.log, "make app in \(mainCheckout) exited \(result.exitCode)")
            return (result.succeeded, Self.outputTail(stdout: result.stdout, stderr: result.stderr))
        } catch {
            KanbanCodeLog.warn(Self.log, "make app in \(mainCheckout) failed: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    /// `DEVELOPER_DIR` points at the pinned Xcode only when that Xcode is installed.
    static func rebuildEnvironment(base: [String: String], xcodeInstalled: Bool) -> [String: String] {
        var env = base
        if xcodeInstalled { env["DEVELOPER_DIR"] = xcodeDeveloperDir }
        return env
    }

    /// The last `lines` lines of stdout followed by stderr.
    static func outputTail(stdout: String, stderr: String, lines: Int = outputTailLines) -> String {
        let all = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return all.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }
}
