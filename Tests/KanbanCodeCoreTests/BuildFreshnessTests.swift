import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("BuildFreshness")
struct BuildFreshnessTests {
    /// A throwaway git repo on branch `main` with one empty commit.
    private final class Repo {
        let path: String

        init() throws {
            path = NSTemporaryDirectory() + "build-freshness-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            try git("init", "-q", "-b", "main")
            try commit("c0")
        }

        deinit { try? FileManager.default.removeItem(atPath: path) }

        @discardableResult
        func git(_ args: String...) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"] + args
            process.currentDirectoryURL = URL(fileURLWithPath: path)
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "git", code: Int(process.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed"])
            }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func commit(_ message: String) throws { try git("commit", "-q", "--allow-empty", "-m", message) }
        func head() throws -> String { try git("rev-parse", "HEAD") }

        func info(sha: String, branch: String? = "main") -> BuildInfo {
            BuildInfo(branch: branch, sha: sha, sourceRepo: path)
        }
    }

    @Test func currentWhenShaIsBranchTip() async throws {
        let repo = try Repo()
        let result = await BuildFreshness.check(repo.info(sha: try repo.head()))
        #expect(result == .current)
    }

    @Test func behindCountsNewCommits() async throws {
        let repo = try Repo()
        let built = try repo.head()
        try repo.commit("c1")
        try repo.commit("c2")
        #expect(await BuildFreshness.check(repo.info(sha: built)) == .behind(commits: 2))
    }

    @Test func deletedBranchComparesWithHead() async throws {
        let repo = try Repo()
        try repo.git("checkout", "-q", "-b", "feat/x")
        try repo.commit("c1")
        let built = try repo.head()
        try repo.git("checkout", "-q", "main")
        try repo.git("merge", "-q", "--ff-only", "feat/x")
        try repo.commit("c2")
        try repo.git("branch", "-q", "-d", "feat/x")
        #expect(await BuildFreshness.check(repo.info(sha: built, branch: "feat/x")) == .behind(commits: 1))
    }

    @Test func detachedBuildComparesWithHead() async throws {
        let repo = try Repo()
        let built = try repo.head()
        try repo.commit("c1")
        #expect(await BuildFreshness.check(repo.info(sha: built, branch: "HEAD")) == .behind(commits: 1))
    }

    @Test func amendedBranchIsDiverged() async throws {
        let repo = try Repo()
        try repo.commit("c1")
        let built = try repo.head()
        try repo.git("commit", "-q", "--amend", "--allow-empty", "-m", "c1 amended")
        #expect(await BuildFreshness.check(repo.info(sha: built)) == .diverged)
    }

    @Test func resetBackIsDiverged() async throws {
        let repo = try Repo()
        try repo.commit("c1")
        let built = try repo.head()
        try repo.git("reset", "-q", "--hard", "HEAD~1")
        #expect(await BuildFreshness.check(repo.info(sha: built)) == .diverged)
    }

    @Test func missingPathIsSourcesNotFound() async throws {
        let repo = try Repo()
        let info = BuildInfo(branch: "main", sha: try repo.head(), sourceRepo: repo.path + "/gone", worktree: "wt1")
        #expect(await BuildFreshness.check(info) == .sourcesNotFound)
    }

    @Test func plainFolderIsSourcesNotFound() async throws {
        let repo = try Repo()
        let plain = NSTemporaryDirectory() + "plain-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: plain) }
        let info = BuildInfo(branch: "main", sha: try repo.head(), sourceRepo: plain)
        #expect(await BuildFreshness.check(info) == .sourcesNotFound)
    }

    @Test func unknownShaIsUnknown() async throws {
        let repo = try Repo()
        let result = await BuildFreshness.check(repo.info(sha: "0000000000000000000000000000000000000001"))
        #expect(result == .unknown)
    }

    @Test func missingFieldsAreUnknown() async {
        #expect(await BuildFreshness.check(BuildInfo(branch: "main", sha: "abc")) == .unknown)
        #expect(await BuildFreshness.check(BuildInfo(branch: "main", sourceRepo: "/r")) == .unknown)
    }

    @Test func textForOneAndManyCommits() {
        #expect(BuildFreshness.behind(commits: 1).text == "Behind its sources by 1 commit")
        #expect(BuildFreshness.behind(commits: 3).text == "Behind its sources by 3 commits")
    }
}
