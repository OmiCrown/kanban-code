import Foundation

/// Whether a build is behind the local sources it was made from. Local git only: no fetch, no network.
public enum BuildFreshness: Equatable, Sendable {
    case current
    case behind(commits: Int)
    /// The build's commit is no longer an ancestor of the branch tip (amended, rebased or reset since).
    case diverged
    /// The source folder or its repository is gone.
    case sourcesNotFound
    /// Git failed, timed out, or does not know the build's commit.
    case unknown

    public var text: String {
        switch self {
        case .current: "Up to date with its sources"
        case .behind(let commits): "Behind its sources by \(commits) \(commits == 1 ? "commit" : "commits")"
        case .diverged: "Branch moved since this build (rebased or reset)"
        case .sourcesNotFound: "Sources not found"
        case .unknown: "Could not check"
        }
    }

    /// Compares the build's commit with the tip of its branch in `info.sourceRepo`, or with that repo's
    /// `HEAD` when the build came from a detached HEAD or the branch no longer exists.
    public static func check(_ info: BuildInfo) async -> BuildFreshness {
        guard let repo = info.sourceRepo, let sha = info.sha,
              sha.range(of: "^[0-9a-fA-F]{4,64}$", options: .regularExpression) != nil else { return .unknown }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repo, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .sourcesNotFound
        }

        let git = ShellCommand.findExecutable("git") ?? "/usr/bin/git"
        func run(_ arguments: [String]) async -> ShellCommand.Result? {
            try? await ShellCommand.run(git, arguments: arguments, currentDirectory: repo, timeout: 10)
        }

        guard let inside = await run(["rev-parse", "--is-inside-work-tree"]) else { return .unknown }
        guard inside.succeeded, inside.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return .sourcesNotFound
        }

        var tip: String?
        if let branch = info.branch, branch != "HEAD",
           let result = await run(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"]), result.succeeded {
            tip = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if tip == nil {
            guard let result = await run(["rev-parse", "HEAD"]), result.succeeded else { return .unknown }
            tip = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let tip, !tip.isEmpty else { return .unknown }

        if tip == sha { return .current }

        guard let ancestor = await run(["merge-base", "--is-ancestor", sha, tip]) else { return .unknown }
        switch ancestor.exitCode {
        case 0:
            guard let count = await run(["rev-list", "--count", "\(sha)..\(tip)"]), count.succeeded,
                  let commits = Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) else { return .unknown }
            return .behind(commits: commits)
        case 1:
            return .diverged
        default:
            return .unknown
        }
    }
}
