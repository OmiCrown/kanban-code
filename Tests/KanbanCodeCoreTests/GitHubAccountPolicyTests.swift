import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("GitHubAccountPolicy")
struct GitHubAccountPolicyTests {
    private let home = "/Users/test"

    private var client: ClaudeProfile {
        ClaudeProfile(path: "/Users/test/.claude-Client", enabled: true,
                      githubUser: "omi-client", projectRoots: ["~/Repos/Client"],
                      githubOwners: ["Client", "client-app"], home: home)
    }
    private var omi: ClaudeProfile {
        ClaudeProfile(path: "/Users/test/.claude-Omicrown", enabled: true,
                      githubUser: "omi-personal", projectRoots: ["~/Repos/Omicrown"], home: home)
    }

    @Test func repoInsideRootBelongsToProfile() {
        let p = GitHubAccountPolicy.profile(forRepoPath: "/Users/test/Repos/Client/app", in: [omi, client])
        #expect(p?.name == "Client")
        #expect(GitHubAccountPolicy.profile(forRepoPath: "/Users/test/Repos/Client", in: [client])?.name == "Client")
    }

    @Test func lookalikeFolderIsNotInsideRoot() {
        #expect(GitHubAccountPolicy.profile(forRepoPath: "/Users/test/Repos/ClientX/app", in: [client]) == nil)
        #expect(GitHubAccountPolicy.profile(forRepoPath: "/Users/test/Repos/Other/app", in: [client]) == nil)
    }

    @Test func longestRootWins() {
        let inner = ClaudeProfile(path: "/Users/test/.claude-Work", enabled: true,
                                  projectRoots: ["~/Repos/Client/work-side"], home: home)
        let p = GitHubAccountPolicy.profile(forRepoPath: "/Users/test/Repos/Client/work-side/x", in: [client, inner])
        #expect(p?.name == "Work")
    }

    @Test func unmanagedOutsideEveryRoot() {
        #expect(GitHubAccountPolicy.verdict(repoPath: "/tmp/x", owner: "anyone", profiles: [client]) == .unmanaged)
    }

    @Test func listedOwnerAndUserAreAllowedIgnoringCase() {
        for owner in ["client", "CLIENT-APP", "omi-client"] {
            let v = GitHubAccountPolicy.verdict(repoPath: "/Users/test/Repos/Client/a", owner: owner, profiles: [client])
            #expect(v == .allowed(profilePath: client.path, githubUser: "omi-client"), "\(owner)")
        }
    }

    @Test func ownerOutsideTheListIsForeign() {
        let v = GitHubAccountPolicy.verdict(repoPath: "/Users/test/Repos/Client/a", owner: "omi-personal", profiles: [client])
        #expect(v == .foreignOwner(profilePath: client.path, profileName: "Client", owner: "omi-personal"))
    }

    @Test func emptyOwnerListOrMissingOwnerChecksNothing() {
        let a = GitHubAccountPolicy.verdict(repoPath: "/Users/test/Repos/Omicrown/a", owner: "whoever", profiles: [omi])
        #expect(a == .allowed(profilePath: omi.path, githubUser: "omi-personal"))
        let b = GitHubAccountPolicy.verdict(repoPath: "/Users/test/Repos/Client/a", owner: nil, profiles: [client])
        #expect(b == .allowed(profilePath: client.path, githubUser: "omi-client"))
    }

    @Test func githubFieldsRoundTripAndSurviveBadValues() throws {
        let data = try JSONEncoder().encode([client])
        let back = try JSONDecoder().decode([ClaudeProfile].self, from: data)
        #expect(back == [client])
        let bad = #"[{"path":"/Users/test/.claude-A","githubUser":5,"projectRoots":"x","githubOwners":["a"]}]"#
        let decoded = try JSONDecoder().decode([ClaudeProfile].self, from: Data(bad.utf8))
        #expect(decoded[0].githubUser == nil)
        #expect(decoded[0].projectRoots.isEmpty)
        #expect(decoded[0].githubOwners == ["a"])
    }
}
