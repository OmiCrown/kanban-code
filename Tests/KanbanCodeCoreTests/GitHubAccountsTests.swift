import Testing
import Foundation
@testable import KanbanCodeCore

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var users: [String] = []
    func add(_ user: String) { lock.withLock { users.append(user) } }
    var all: [String] { lock.withLock { users } }
}

@Suite("GitHubAccounts")
struct GitHubAccountsTests {
    private let home = "/Users/test"
    private let clientRepo = "/Users/test/Repos/Client/app"
    private let otherRepo = "/Users/test/Repos/Other/x"

    private var client: ClaudeProfile {
        ClaudeProfile(path: "/Users/test/.claude-Client", enabled: true, githubUser: "omi-client",
                      projectRoots: ["~/Repos/Client"], githubOwners: ["client"], home: home)
    }

    private func accounts(tokens: [String: String], calls: Calls = Calls()) -> GitHubAccounts {
        let a = GitHubAccounts(fetchToken: { user in calls.add(user); return tokens[user] })
        a.setProfiles([client])
        return a
    }

    @Test func managedRepoGetsItsProfileToken() async {
        let env = await accounts(tokens: ["omi-client": "tok-client"]).environment(forRepo: clientRepo)
        #expect(env?["GH_TOKEN"] == "tok-client")
        #expect(env?["GITHUB_TOKEN"] == nil)
    }

    @Test func unmanagedRepoKeepsTheActiveAccount() async {
        let calls = Calls()
        let a = accounts(tokens: ["omi-client": "tok-client"], calls: calls)
        #expect(await a.environment(forRepo: otherRepo) == nil)
        #expect(await a.problem(forRepo: otherRepo, owner: "anyone") == nil)
        #expect(calls.all.isEmpty)
    }

    @Test func foreignOwnerIsAProblem() async {
        let p = await accounts(tokens: ["omi-client": "t"]).problem(forRepo: clientRepo, owner: "omi-personal")
        #expect(p == .foreignOwner(profileName: "Client", owner: "omi-personal", allowed: ["client", "omi-client"]))
    }

    @Test func missingTokenIsAProblemAndNoEnvironment() async {
        let a = accounts(tokens: [:])
        #expect(await a.environment(forRepo: clientRepo) == nil)
        #expect(await a.problem(forRepo: clientRepo, owner: "client") == .noToken(profileName: "Client", githubUser: "omi-client"))
    }

    @Test func allowedOwnerWithTokenHasNoProblem() async {
        #expect(await accounts(tokens: ["omi-client": "t"]).problem(forRepo: clientRepo, owner: "Client") == nil)
    }

    @Test func tokenIsFetchedOnceThenReused() async {
        let calls = Calls()
        let a = accounts(tokens: ["omi-client": "t"], calls: calls)
        let t0 = Date()
        _ = await a.environment(forRepo: clientRepo, now: t0)
        _ = await a.environment(forRepo: clientRepo, now: t0.addingTimeInterval(30))
        #expect(calls.all == ["omi-client"])
        _ = await a.environment(forRepo: clientRepo, now: t0.addingTimeInterval(700))
        #expect(calls.all.count == 2)
    }

    @Test func missingTokenIsNotRetriedEveryPoll() async {
        let calls = Calls()
        let a = accounts(tokens: [:], calls: calls)
        let t0 = Date()
        _ = await a.environment(forRepo: clientRepo, now: t0)
        _ = await a.environment(forRepo: clientRepo, now: t0.addingTimeInterval(10))
        #expect(calls.all.count == 1)
        _ = await a.environment(forRepo: clientRepo, now: t0.addingTimeInterval(90))
        #expect(calls.all.count == 2)
    }
}
