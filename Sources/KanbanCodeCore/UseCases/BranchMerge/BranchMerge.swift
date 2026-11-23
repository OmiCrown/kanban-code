import Foundation

/// Merges a card's worktree branch into the main checkout, fast-forward only.
/// `preflight` only reads repository state.
public struct BranchMerge: Sendable {
    let run: GitRepoSync.Runner

    public init(run: @escaping GitRepoSync.Runner = GitRepoSync.shell) {
        self.run = run
    }

    /// Reads the layout, the relation of `branch` to the main checkout's branch and
    /// the uncommitted paths on both sides. Throws `BranchMergeError.refused` when
    /// `worktreePath` is not a live worktree of `branch`.
    public func preflight(worktreePath: String, branch: String) async throws -> MergePreflight {
        guard FileManager.default.fileExists(atPath: worktreePath) else {
            throw BranchMergeError.refused("The worktree \(worktreePath) no longer exists.")
        }
        let list = await run(["worktree", "list", "--porcelain"], worktreePath)
        guard list.succeeded else {
            throw BranchMergeError.refused("Cannot list worktrees: \(GitRepoSync.firstLine(list))")
        }
        let records = Self.parseWorktrees(list.stdout)
        // The first record of `git worktree list` is always the main checkout.
        guard let main = records.first else {
            throw BranchMergeError.refused("git reported no worktrees for \(worktreePath).")
        }
        let wanted = Self.canonical(worktreePath)
        guard let record = records.first(where: { Self.canonical($0.path) == wanted }) else {
            throw BranchMergeError.refused("\(worktreePath) is not a worktree of this repository.")
        }
        guard record.path != main.path else {
            throw BranchMergeError.refused("\(worktreePath) is the main checkout, not a task worktree.")
        }
        guard record.branch == "refs/heads/\(branch)" else {
            let actual = record.branch.map { $0.replacingOccurrences(of: "refs/heads/", with: "") } ?? "a detached HEAD"
            throw BranchMergeError.refused("The worktree is on \(actual), not on \(branch).")
        }

        let mainCheckout = main.path
        let head = await run(["symbolic-ref", "--short", "-q", "HEAD"], mainCheckout)
        let current = head.succeeded ? head.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let currentBranch: String? = current.isEmpty ? nil : current
        let onMain = currentBranch == "main" || currentBranch == "master"

        let mainDirty = await dirtyPaths(in: mainCheckout)
        let worktreeDirty = await dirtyPaths(in: worktreePath)

        var relation: BranchRelation = .mainNotOnMain(current: currentBranch)
        if onMain, let mainName = currentBranch {
            relation = try await relate(branch: branch, to: mainName, in: mainCheckout)
        }
        return MergePreflight(
            mainCheckout: mainCheckout,
            mainBranch: onMain ? currentBranch : nil,
            branch: branch,
            worktreePath: worktreePath,
            relation: relation,
            mainDirtyPaths: mainDirty,
            worktreeDirtyPaths: worktreeDirty,
            docs: []
        )
    }

    // MARK: - Relation

    private func relate(branch: String, to mainName: String, in mainCheckout: String) async throws -> BranchRelation {
        let mainRef = "refs/heads/\(mainName)"
        let branchRef = "refs/heads/\(branch)"
        let counts = await run(["rev-list", "--left-right", "--count", "\(mainRef)...\(branchRef)"], mainCheckout)
        let numbers = counts.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).compactMap { Int($0) }
        guard counts.succeeded, numbers.count == 2 else {
            throw BranchMergeError.refused("Cannot compare \(branch) with \(mainName): \(GitRepoSync.firstLine(counts))")
        }
        let (behind, ahead) = (numbers[0], numbers[1])
        if ahead == 0 { return .upToDate }
        let aheadCommits = try await commits("\(mainRef)..\(branchRef)", in: mainCheckout)
        if behind == 0 { return .fastForward(commits: aheadCommits) }
        let behindCommits = try await commits("\(branchRef)..\(mainRef)", in: mainCheckout)
        return .diverged(ahead: aheadCommits, behind: behindCommits)
    }

    /// The commits of `range`, oldest first.
    private func commits(_ range: String, in dir: String) async throws -> [CommitLine] {
        let log = await run(["log", "--reverse", "--format=%h%x00%s", range], dir)
        guard log.succeeded else {
            throw BranchMergeError.refused("Cannot list commits \(range): \(GitRepoSync.firstLine(log))")
        }
        return log.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{0}", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return CommitLine(sha: String(parts[0]), subject: String(parts[1]))
        }
    }

    // MARK: - Dirty paths

    private func dirtyPaths(in dir: String) async -> [String] {
        let status = await run(["status", "--porcelain=v1", "-z"], dir)
        guard status.succeeded else { return [] }
        return Self.parseStatus(status.stdout)
    }

    /// Paths from `status --porcelain=v1 -z`: entries `XY path`, NUL separated; a
    /// rename or copy is followed by one extra entry holding the source path. The
    /// shell runner trims whitespace, which can eat the leading space of the first
    /// entry (` M path` arrives as `M path`).
    static func parseStatus(_ output: String) -> [String] {
        let entries = output.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)
        var paths: [String] = []
        var index = 0
        while index < entries.count {
            let entry = entries[index]
            index += 1
            let chars = Array(entry)
            guard chars.count >= 3 else { continue }
            let pathStart: Int
            if chars[2] == " " {
                pathStart = 3
            } else if chars[1] == " " {
                pathStart = 2  // leading space trimmed
            } else {
                continue
            }
            let codes = chars[0..<min(2, pathStart)]
            paths.append(String(chars[pathStart...]))
            if codes.contains("R") || codes.contains("C") { index += 1 }
        }
        return paths
    }

    // MARK: - Worktree list

    struct WorktreeRecord: Equatable {
        var path: String
        var branch: String?
    }

    static func parseWorktrees(_ output: String) -> [WorktreeRecord] {
        var records: [WorktreeRecord] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                records.append(WorktreeRecord(path: String(line.dropFirst("worktree ".count)), branch: nil))
            } else if line.hasPrefix("branch "), !records.isEmpty {
                records[records.count - 1].branch = String(line.dropFirst("branch ".count))
            }
        }
        return records
    }

    /// `realpath` of an existing path (so `/var` and `/private/var` compare equal), else the path itself.
    static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
