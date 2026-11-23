import Foundation

@testable import KanbanCodeCore

/// A throwaway git repository `<root>/main` with one commit on `main`.
struct GitFixture {
    let root: String
    let repo: String

    static func make() async throws -> GitFixture {
        let base = (NSTemporaryDirectory() as NSString).appendingPathComponent("branch-merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        // /var -> /private/var: git reports the realpath.
        let root = BranchMerge.canonical(base)
        let repo = root + "/main"
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        let fixture = GitFixture(root: root, repo: repo)
        try await fixture.git(["init", "-q", "-b", "main"], in: repo)
        try await fixture.git(["config", "user.email", "test@example.com"], in: repo)
        try await fixture.git(["config", "user.name", "Test"], in: repo)
        try await fixture.git(["config", "commit.gpgsign", "false"], in: repo)
        try fixture.write(".git/info/exclude", in: repo, ".superpowers/\n")
        try await fixture.commit(in: repo, file: "README.md", content: "base\n")
        return fixture
    }

    /// Adds a worktree on a new `branch`. `sibling` puts it at `<root>/repo.worktrees/<name>`,
    /// otherwise at `<repo>/.claude/worktrees/<name>`.
    func addWorktree(_ name: String, branch: String, sibling: Bool) async throws -> String {
        let dir = sibling ? "\(root)/repo.worktrees/\(name)" : "\(repo)/.claude/worktrees/\(name)"
        try FileManager.default.createDirectory(
            atPath: (dir as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try await git(["worktree", "add", "-q", "-b", branch, dir, "main"], in: repo)
        return dir
    }

    func commit(in dir: String, file: String, content: String) async throws {
        try write(file, in: dir, content)
        try await git(["add", "--", file], in: dir)
        try await git(["commit", "-q", "-m", "add \(file)"], in: dir)
    }

    func write(_ path: String, in dir: String, _ content: String) throws {
        let full = dir + "/" + path
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try content.write(toFile: full, atomically: true, encoding: .utf8)
    }

    @discardableResult
    func git(_ args: [String], in dir: String) async throws -> String {
        let result = try await ShellCommand.run("/usr/bin/env", arguments: ["git"] + args, currentDirectory: dir)
        guard result.succeeded else {
            throw FixtureError.git(args.joined(separator: " "), result.stderr)
        }
        return result.stdout
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: root)
    }

    enum FixtureError: Error { case git(String, String) }
}
