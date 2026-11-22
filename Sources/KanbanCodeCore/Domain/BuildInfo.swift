import Foundation

/// What `make app` stamped into `Info.plist` about the build (see `Scripts/build-info-plist.sh`):
/// which commit, branch and worktree it came from, and when it was built.
public struct BuildInfo: Equatable, Sendable {
    public let describe: String?
    /// `HEAD` when the build was made from a detached HEAD.
    public let branch: String?
    public let sha: String?
    public let dirty: Bool
    public let buildDate: Date?
    public let sourceRepo: String?
    /// Folder name of the linked worktree the build came from; nil for the main checkout.
    public let worktree: String?

    public static let devRunText = "Dev run — not built with make app"

    private enum Key {
        static let describe = "KCGitDescribe"
        static let branch = "KCGitBranch"
        static let sha = "KCGitSHA"
        static let dirty = "KCGitDirty"
        static let buildDate = "KCBuildDate"
        static let sourceRepo = "KCSourceRepo"
        static let worktree = "KCWorktree"
        static let all = [describe, branch, sha, dirty, buildDate, sourceRepo, worktree]
    }

    public init(describe: String? = nil, branch: String? = nil, sha: String? = nil, dirty: Bool = false,
                buildDate: Date? = nil, sourceRepo: String? = nil, worktree: String? = nil) {
        self.describe = describe
        self.branch = branch
        self.sha = sha
        self.dirty = dirty
        self.buildDate = buildDate
        self.sourceRepo = sourceRepo
        self.worktree = worktree
    }

    /// Nil when the dictionary carries none of the `KC*` keys (for example `swift run`).
    public init?(infoDictionary: [String: Any]?) {
        guard let dict = infoDictionary, Key.all.contains(where: { dict[$0] != nil }) else { return nil }
        func string(_ key: String) -> String? {
            guard let value = dict[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        self.init(
            describe: string(Key.describe),
            branch: string(Key.branch),
            sha: string(Key.sha),
            dirty: string(Key.dirty) == "true",
            buildDate: string(Key.buildDate).flatMap { ISO8601DateFormatter().date(from: $0) },
            sourceRepo: string(Key.sourceRepo),
            worktree: string(Key.worktree)
        )
    }

    /// A build made on a CI runner carries a commit but no local source path, so there is nothing to compare with.
    public var canCheckFreshness: Bool { sourceRepo != nil && sha != nil }

    public var shortSHA: String? { sha.map { String($0.prefix(7)) } }

    public var commitText: String? {
        guard let short = shortSHA else { return nil }
        return dirty ? "\(short) (dirty)" : short
    }

    public func buildDateText(in timeZone: TimeZone = .current) -> String? {
        guard let buildDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        return formatter.string(from: buildDate)
    }

    /// One `Label: value` line per known value, in display order; also what the About window copies.
    public func summaryText(freshness: BuildFreshness?, timeZone: TimeZone = .current) -> String {
        let rows: [(String, String?)] = [
            ("Version", describe),
            ("Branch", branch),
            ("Worktree", worktree),
            ("Commit", commitText),
            ("Built", buildDateText(in: timeZone)),
            ("Sources", freshness?.text),
        ]
        return rows.compactMap { label, value in value.map { "\(label): \($0)" } }.joined(separator: "\n")
    }
}
