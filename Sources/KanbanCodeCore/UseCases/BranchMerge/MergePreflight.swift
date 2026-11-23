import Foundation

/// One commit, as listed in the merge dialog.
public struct CommitLine: Sendable, Equatable {
    public var sha: String
    public var subject: String

    public init(sha: String, subject: String) {
        self.sha = sha
        self.subject = subject
    }
}

/// How a worktree branch relates to the branch checked out in the main checkout.
public enum BranchRelation: Sendable, Equatable {
    /// The branch is ahead of main and main has nothing the branch lacks.
    /// `commits` are the ones that would land, oldest first.
    case fastForward(commits: [CommitLine])
    /// Main already contains every commit of the branch.
    case upToDate
    /// Both sides have commits the other lacks (oldest first).
    case diverged(ahead: [CommitLine], behind: [CommitLine])
    /// The main checkout is not on `main` or `master` (`current` is nil when detached).
    case mainNotOnMain(current: String?)
}

/// A documentation file in the worktree that could be carried to the main checkout.
public struct DocCandidate: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        /// Absent from the main checkout.
        case new
        /// Present in the main checkout with the same content.
        case identical
        /// Present in the main checkout with other content.
        case different
    }

    public var path: String
    public var state: State
    public var id: String { path }

    public init(path: String, state: State) {
        self.path = path
        self.state = state
    }
}

/// Everything the Merge dialog needs to know before it offers the merge.
public struct MergePreflight: Sendable, Equatable {
    public var mainCheckout: String
    /// The branch checked out in the main checkout when it is `main` or `master`.
    public var mainBranch: String?
    public var branch: String
    public var worktreePath: String
    public var relation: BranchRelation
    /// Uncommitted paths in the main checkout. Listed for the user; they do not block.
    public var mainDirtyPaths: [String]
    /// Uncommitted paths in the worktree. They do not travel with the merge.
    public var worktreeDirtyPaths: [String]
    public var docs: [DocCandidate]

    public init(
        mainCheckout: String,
        mainBranch: String?,
        branch: String,
        worktreePath: String,
        relation: BranchRelation,
        mainDirtyPaths: [String] = [],
        worktreeDirtyPaths: [String] = [],
        docs: [DocCandidate] = []
    ) {
        self.mainCheckout = mainCheckout
        self.mainBranch = mainBranch
        self.branch = branch
        self.worktreePath = worktreePath
        self.relation = relation
        self.mainDirtyPaths = mainDirtyPaths
        self.worktreeDirtyPaths = worktreeDirtyPaths
        self.docs = docs
    }

    /// Why the merge cannot go ahead, or nil when it can.
    public var blockReason: String? {
        switch relation {
        case .mainNotOnMain(let current):
            return "The main checkout is on \(current.map { "'\($0)'" } ?? "a detached HEAD"), not main or master."
        case .diverged(let ahead, let behind):
            return "\(branch) and \(mainBranch ?? "main") have diverged (\(ahead.count) ahead, \(behind.count) behind); rebase \(branch) first."
        case .fastForward, .upToDate:
            if docs.contains(where: { $0.state == .different }) {
                return "A documentation file differs in \(mainBranch ?? "the main checkout"); resolve it first."
            }
            if case .upToDate = relation, !docs.contains(where: { $0.state == .new }) {
                return "\(branch) is already contained in \(mainBranch ?? "the main branch"); nothing to merge."
            }
            return nil
        }
    }
}

public enum BranchMergeError: Error, Equatable, LocalizedError {
    case refused(String)

    public var errorDescription: String? {
        switch self {
        case .refused(let reason): return reason
        }
    }
}
