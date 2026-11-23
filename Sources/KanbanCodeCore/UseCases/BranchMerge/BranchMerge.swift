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

        let mainDirty = try await dirtyPaths(in: mainCheckout)
        let worktreeDirty = try await dirtyPaths(in: worktreePath)
        let docs = try await untrackedDocs(worktree: worktreePath, mainCheckout: mainCheckout)

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
            docs: docs
        )
    }

    // MARK: - Merge

    private static let log = "merge"

    /// Fast-forwards the main checkout's branch to `branch`, then carries the chosen
    /// documentation files over. Re-runs `preflight` first, so a state that changed since
    /// the dialog was shown is refused. A refusal or a failed `git merge` leaves the main
    /// checkout as it was: documentation is checked before the merge and copied only after it succeeded.
    public func merge(worktreePath: String, branch: String, carryDocs: [String]) async -> MergeOutcome {
        let state: MergePreflight
        do {
            state = try await preflight(worktreePath: worktreePath, branch: branch)
        } catch {
            return refuse(error.localizedDescription)
        }
        if let reason = state.blockReason { return refuse(reason) }

        let wanted = Set(carryDocs)
        let identical = state.docs.filter { $0.state == .identical }.map(\.path)
        let toCopy = state.docs.filter { $0.state == .new && wanted.contains($0.path) }.map(\.path)

        // A doc that cannot be carried stops the merge here, while main is still untouched.
        // A relation that cannot merge is refused by blockReason above.
        for path in toCopy {
            if let problem = Self.docProblem(path, from: worktreePath, to: state.mainCheckout) {
                return refuse("\(path) cannot be carried into \(state.mainBranch ?? "the main checkout"): \(problem). Deselect it or fix it first; nothing was merged.")
            }
        }

        switch state.relation {
        case .upToDate:
            let (copied, skipped) = carry(toCopy, identical: identical, from: worktreePath, to: state.mainCheckout)
            KanbanCodeLog.info(Self.log, "\(branch) already in \(state.mainBranch ?? "main"); carried \(copied.count) doc(s), skipped \(skipped.count)")
            return .alreadyInMain(copied: copied, skipped: skipped)

        case .fastForward:
            let before = await run(["rev-parse", "HEAD"], state.mainCheckout)
            guard before.succeeded else {
                return refuse("Cannot read HEAD of \(state.mainCheckout): \(GitRepoSync.firstLine(before))")
            }
            let oldHead = before.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

            let merged = await run(["merge", "--ff-only", "refs/heads/\(branch)"], state.mainCheckout)
            guard merged.succeeded else {
                let text = (merged.stderr.isEmpty ? merged.stdout : merged.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
                return refuse(text.isEmpty ? "git merge failed with exit code \(merged.exitCode)." : text)
            }

            let after = await run(["rev-parse", "HEAD"], state.mainCheckout)
            let newHead = after.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard after.succeeded, !newHead.isEmpty else {
                return refuse("\(branch) was merged, but HEAD of \(state.mainCheckout) cannot be read: \(GitRepoSync.firstLine(after)). No documentation was copied.")
            }
            let (copied, skipped) = carry(toCopy, identical: identical, from: worktreePath, to: state.mainCheckout)
            KanbanCodeLog.info(Self.log, "merged \(branch) into \(state.mainBranch ?? "main") \(oldHead.prefix(8))..\(newHead.prefix(8)); carried \(copied.count) doc(s), skipped \(skipped.count)")
            return .merged(oldHead: oldHead, newHead: newHead, copied: copied, skipped: skipped)

        case .diverged, .mainNotOnMain:
            // blockReason is non-nil for both; kept for exhaustiveness.
            return refuse("\(branch) cannot be fast-forwarded into the main checkout.")
        }
    }

    private func refuse(_ text: String) -> MergeOutcome {
        KanbanCodeLog.warn(Self.log, "refused: \(text)")
        return .refused(text)
    }

    // MARK: - Carrying docs

    /// Copies each of `paths` from the worktree into the main checkout and returns the
    /// copied paths and the skipped ones (`identical` first, then every file that failed a
    /// guard). Never replaces a file and never writes through a symlink.
    private func carry(_ paths: [String], identical: [String], from worktree: String, to mainCheckout: String) -> (copied: [String], skipped: [String]) {
        var copied: [String] = []
        var skipped = identical
        for path in paths {
            if let problem = Self.copyDoc(path, from: worktree, to: mainCheckout) {
                KanbanCodeLog.warn(Self.log, "not copying \(path): \(problem)")
                skipped.append(path)
            } else {
                copied.append(path)
            }
        }
        return (copied, skipped)
    }

    private enum Kind { case absent, directory, regular, symlink, other, unreadable }

    /// `lstat` of `path`: a symlink is reported as such, never followed. Only ENOENT means
    /// absent; any other error is `unreadable`, which callers must not treat as absent.
    private static func kind(of path: String) -> Kind {
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT ? .absent : .unreadable }
        switch info.st_mode & S_IFMT {
        case S_IFREG: return .regular
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    /// Why `path` cannot be carried into the main checkout right now, or nil when it can.
    /// Reads with `lstat` only; never writes. Run before the merge (so a problem refuses it)
    /// and again right before each copy (the state may have moved since).
    private static func docProblem(_ path: String, from worktree: String, to mainCheckout: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts[0] == "docs", !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return "it is not a path under docs/"
        }
        // The source: real directories down to a regular file, no symlink anywhere on the way.
        var source = worktree
        for part in parts.dropLast() {
            source += "/" + part
            switch kind(of: source) {
            case .directory: continue
            case .symlink: return "\(source) is a symlink"
            default: return "\(source) is not a readable directory"
            }
        }
        guard kind(of: source + "/" + parts[parts.count - 1]) == .regular else {
            return "the source is not a regular file"
        }
        // Every existing parent under main must be a real directory; the first missing one
        // (and so everything below it) is created by the copy.
        var current = mainCheckout
        for part in parts.dropLast() {
            current += "/" + part
            switch kind(of: current) {
            case .directory: continue
            case .absent: break
            case .symlink: return "\(current) is a symlink"
            case .regular, .other: return "\(current) is not a directory"
            case .unreadable: return "\(current) cannot be read"
            }
            break
        }
        switch kind(of: mainCheckout + "/" + path) {
        case .absent: return nil
        case .symlink: return "\(mainCheckout + "/" + path) is a symlink"
        case .directory, .regular, .other: return "\(mainCheckout + "/" + path) already exists"
        case .unreadable: return "\(mainCheckout + "/" + path) cannot be read"
        }
    }

    /// Copies one `docs/...` file. Returns nil on success, else why it was not copied.
    private static func copyDoc(_ path: String, from worktree: String, to mainCheckout: String) -> String? {
        if let problem = docProblem(path, from: worktree, to: mainCheckout) { return problem }
        let destination = mainCheckout + "/" + path
        do {
            try FileManager.default.createDirectory(
                atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: worktree + "/" + path, toPath: destination)
            return nil
        } catch {
            return error.localizedDescription
        }
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

    /// `--no-optional-locks` keeps a read-only preflight from refreshing the index or
    /// taking `index.lock` in the main checkout. A failing `git status` throws: an
    /// unreadable tree must not look clean.
    private func dirtyPaths(in dir: String) async throws -> [String] {
        let status = await run(["--no-optional-locks", "status", "--porcelain=v1", "-z"], dir)
        guard status.succeeded else {
            throw BranchMergeError.refused("Cannot read the git status of \(dir): \(GitRepoSync.firstLine(status))")
        }
        return Self.parseStatus(status.stdout)
    }

    // MARK: - Docs

    /// Untracked, non-ignored regular files under `docs/` of the worktree, compared
    /// with the same relative path in the main checkout, sorted by path. Reads only.
    private func untrackedDocs(worktree: String, mainCheckout: String) async throws -> [DocCandidate] {
        let listing = await run(["ls-files", "--others", "--exclude-standard", "-z", "--", "docs/"], worktree)
        guard listing.succeeded else {
            throw BranchMergeError.refused("Cannot list documentation files in \(worktree): \(GitRepoSync.firstLine(listing))")
        }
        // Entries are NUL separated; every path starts with `docs/`, so the runner's
        // whitespace trimming cannot eat the start of the first one.
        let paths = listing.stdout.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)
        var docs: [DocCandidate] = []
        for path in paths.sorted() {
            let source = worktree + "/" + path
            // attributesOfItem uses lstat: a symlink reports .typeSymbolicLink and is skipped.
            guard let type = try? FileManager.default.attributesOfItem(atPath: source)[.type] as? FileAttributeType,
                  type == .typeRegular else { continue }
            let target = mainCheckout + "/" + path
            let state: DocCandidate.State
            if (try? FileManager.default.attributesOfItem(atPath: target)) == nil {
                state = .new
            } else if let mine = FileManager.default.contents(atPath: source),
                      let theirs = FileManager.default.contents(atPath: target), mine == theirs {
                state = .identical
            } else {
                state = .different
            }
            docs.append(DocCandidate(path: path, state: state))
        }
        return docs
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
