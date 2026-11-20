import Testing
import Foundation
@testable import KanbanCodeCore

/// `GitHubAccounts.shared` is global: these tests run one at a time and
/// leave it empty.
@Suite("Merge guard by GitHub account", .serialized)
struct GhMergeGuardTests {
    private struct Rig {
        let root: String
        let repo: String
        let marker: String
    }

    private func makeRig(owner: String, profile: ClaudeProfile?) throws -> Rig {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("gh-merge-guard-\(UUID().uuidString)")
        let repo = root + "/Repos/Client/app"
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        for args in [["init", "-q"], ["remote", "add", "origin", "git@github.com:\(owner)/app.git"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = args
            p.currentDirectoryURL = URL(fileURLWithPath: repo)
            try p.run(); p.waitUntilExit()
        }
        GitHubAccounts.shared.setProfiles(profile.map { [$0] } ?? [])
        return Rig(root: root, repo: repo, marker: root + "/merge-ran")
    }

    private func profile(root: String, user: String?, owners: [String]) -> ClaudeProfile {
        ClaudeProfile(path: root + "/.claude-Client", enabled: true, githubUser: user,
                      projectRoots: [root + "/Repos/Client"], githubOwners: owners, home: root)
    }

    private func merge(_ rig: Rig) async throws -> MergeResult {
        // The template is a command: `touch <marker>` shows whether it ran.
        try await GhCliAdapter().mergePR(
            repoRoot: rig.repo, prNumber: 7, commandTemplate: "touch \(rig.marker)")
    }

    @Test func personalRepoInAWorkFolderIsNotMerged() async throws {
        let rig = try makeRig(owner: "omi-personal", profile: nil)
        defer { GitHubAccounts.shared.setProfiles([]); try? FileManager.default.removeItem(atPath: rig.root) }
        GitHubAccounts.shared.setProfiles([profile(root: rig.root, user: nil, owners: ["client"])])
        let result = try await merge(rig)
        guard case .failure(let message) = result else { Issue.record("expected a refusal"); return }
        #expect(message.contains("omi-personal"))
        #expect(message.contains("Client"))
        #expect(!FileManager.default.fileExists(atPath: rig.marker))
    }

    @Test func profileWithoutAGhLoginIsNotMerged() async throws {
        let rig = try makeRig(owner: "client", profile: nil)
        defer { GitHubAccounts.shared.setProfiles([]); try? FileManager.default.removeItem(atPath: rig.root) }
        GitHubAccounts.shared.setProfiles([profile(root: rig.root, user: "no-such-login-\(UUID().uuidString.prefix(8))", owners: ["client"])])
        let result = try await merge(rig)
        guard case .failure(let message) = result else { Issue.record("expected a refusal"); return }
        #expect(message.contains("gh auth login"))
        #expect(!FileManager.default.fileExists(atPath: rig.marker))
    }

    @Test func allowedOwnerWithoutALoginNamedRunsAsBefore() async throws {
        let rig = try makeRig(owner: "client", profile: nil)
        defer { GitHubAccounts.shared.setProfiles([]); try? FileManager.default.removeItem(atPath: rig.root) }
        GitHubAccounts.shared.setProfiles([profile(root: rig.root, user: nil, owners: ["client"])])
        _ = try await merge(rig)
        #expect(FileManager.default.fileExists(atPath: rig.marker))
    }

    @Test func repoOutsideEveryProfileFolderRunsAsBefore() async throws {
        let rig = try makeRig(owner: "omi-personal", profile: nil)
        defer { GitHubAccounts.shared.setProfiles([]); try? FileManager.default.removeItem(atPath: rig.root) }
        GitHubAccounts.shared.setProfiles([ClaudeProfile(
            path: rig.root + "/.claude-X", enabled: true, projectRoots: [rig.root + "/Elsewhere"],
            githubOwners: ["client"], home: rig.root)])
        _ = try await merge(rig)
        #expect(FileManager.default.fileExists(atPath: rig.marker))
    }
}
