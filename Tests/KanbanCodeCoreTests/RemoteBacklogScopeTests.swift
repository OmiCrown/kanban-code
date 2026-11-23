import Foundation
import KanbanCodeRemoteKit
import Testing

@testable import KanbanCodeCore

@Suite("Backlog scope")
struct RemoteBacklogScopeTests {
    private func refusal(_ method: String, _ path: String) -> String? {
        RemoteScopePolicy.refusal(scope: .backlog, method: method, rest: path.split(separator: "/").map(String.init))
    }

    @Test("the three routes of the allow list pass")
    func routesAllowed() {
        #expect(refusal("GET", "me") == nil)
        #expect(refusal("GET", "machines") == nil)
        #expect(refusal("POST", "tasks") == nil)
    }

    @Test("every other route is refused, a route added later included")
    func routesRefused() {
        let routes: [(String, String)] = [
            ("GET", "board"), ("GET", "cards/search"), ("GET", "cards/c1"), ("GET", "cards/c1/transcript"),
            ("POST", "cards/c1/prompt"), ("POST", "cards/c1/interrupt"), ("POST", "cards/c1/resume"),
            ("POST", "cards/c1/move"), ("PATCH", "cards/c1"), ("DELETE", "cards/c1"), ("POST", "cards/c1/fork"),
            ("GET", "cards/c1/terminal"), ("POST", "cli"), ("POST", "vault/secrets"), ("GET", "events"),
            ("POST", "invented/route"), ("GET", "tasks"), ("DELETE", "tasks"),
        ]
        for (method, path) in routes {
            let why = refusal(method, path)
            #expect(why != nil, "\(method) /v1/\(path) was allowed")
            #expect(why == "the backlog scope cannot call \(method) /v1/\(path)")
        }
    }

    @Test("a backlog token does not act for the owner")
    func doesNotActForOwner() {
        #expect(RemoteScope.backlog.actsForOwner == false)
        #expect(RemoteActivityPolicy.actsForOwner(scope: .backlog, header: "1") == false)
    }

    @Test("a backlog device survives the store and authenticates")
    func storeRoundTrips() throws {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("backlog-scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/devices.json"

        let added = try RemoteDeviceStore(path: path).add(name: "claude", scope: .backlog)
        let second = RemoteDeviceStore(path: path)

        #expect(second.list().first?.scope == .backlog)
        #expect(second.authenticate(token: added.token)?.scope == .backlog)
    }

    @Test("the scope is written as \"backlog\"")
    func rawValue() {
        #expect(RemoteScope.backlog.rawValue == "backlog")
        #expect(RemoteScope(rawValue: "backlog") == .backlog)
    }
}

@Suite("Backlog scope on the server")
struct RemoteBacklogScopeServerTests {
    private static let launchRefusal = "the backlog scope only creates backlog cards: send launch=false"
    private static let machineRefusal = "the backlog scope cannot choose another machine"
    private static let urlRefusal = "the backlog scope cannot name a repository URL as the project"

    private func task(_ f: RemoteServerFixture, token: String, project: String = "acme", launch: Bool? = false,
                      machine: String? = nil) async throws -> (Int, String) {
        let body = try JSONEncoder.remote.encode(
            RemoteTaskRequest(project: project, prompt: "x", launch: launch, machine: machine))
        let (status, data) = try await f.request("POST", "/v1/tasks", token: token, body: body)
        return (status, String(decoding: data, as: UTF8.self))
    }

    private func backlogToken(_ f: RemoteServerFixture) throws -> String {
        try f.devices.add(name: "claude", scope: .backlog).token
    }

    @Test("launch=false creates the card")
    func createsABacklogCard() async throws {
        let f = try await RemoteServerFixture()
        defer { f.shutdown() }
        let (status, _) = try await task(f, token: try backlogToken(f))
        #expect(status == 201)
        #expect(f.host.state.withLock { $0.tasks.map(\.launch) } == [false])
    }

    @Test("launch=true is refused and creates nothing")
    func launchTrueRefused() async throws {
        let f = try await RemoteServerFixture()
        defer { f.shutdown() }
        let (status, text) = try await task(f, token: try backlogToken(f), launch: true)
        #expect(status == 403)
        #expect(text.contains(Self.launchRefusal))
        #expect(f.host.state.withLock { $0.tasks.isEmpty })
    }

    @Test("an absent launch is refused, not read as false")
    func launchAbsentRefused() async throws {
        let f = try await RemoteServerFixture()
        defer { f.shutdown() }
        let (status, text) = try await task(f, token: try backlogToken(f), launch: nil)
        #expect(status == 403)
        #expect(text.contains(Self.launchRefusal))
        #expect(f.host.state.withLock { $0.tasks.isEmpty })
    }

    @Test("this master by name or as mac passes, another machine does not")
    func machineAllowedForThisMaster() async throws {
        let f = try await RemoteServerFixture()
        defer { f.shutdown() }
        let token = try backlogToken(f)
        // The fake host lists "rchaves-platform" as the machine of kind this.
        let (thisName, _) = try await task(f, token: token, machine: "rchaves-platform")
        let (shortName, _) = try await task(f, token: token, machine: "MAC")
        #expect(thisName == 201)
        #expect(shortName == 201)
        let (other, text) = try await task(f, token: token, machine: "studio")
        #expect(other == 403)
        #expect(text.contains(Self.machineRefusal))
        #expect(f.host.state.withLock { $0.tasks.count } == 2)
    }

    @Test("a repository URL as the project is refused before the host sees it")
    func repositoryURLRefused() async throws {
        let f = try await RemoteServerFixture()
        defer { f.shutdown() }
        let token = try backlogToken(f)
        for project in ["https://github.com/a/b", "git@github.com:a/b.git"] {
            let (status, text) = try await task(f, token: token, project: project)
            #expect(status == 403, "\(project)")
            #expect(text.contains(Self.urlRefusal), "\(project)")
        }
        #expect(f.host.state.withLock { $0.tasks.isEmpty })
    }

    @Test("every other route is refused")
    func otherRoutesRefused() async throws {
        let f = try await RemoteServerFixture()
        defer { f.shutdown() }
        let token = try backlogToken(f)
        let (board, _) = try await f.request("GET", "/v1/board", token: token)
        let prompt = try JSONEncoder.remote.encode(RemotePromptRequest(text: "hi"))
        let (send, _) = try await f.request("POST", "/v1/cards/c1/prompt", token: token, body: prompt)
        #expect(board == 403)
        #expect(send == 403)
        #expect(f.host.state.withLock { $0.prompts.isEmpty })
    }

    @Test("an agent token without launch still launches")
    func agentTokenUnchanged() async throws {
        let f = try await RemoteServerFixture()
        defer { f.shutdown() }
        let (status, _) = try await task(f, token: f.agentToken, launch: nil, machine: "studio")
        #expect(status == 201)
    }
}
