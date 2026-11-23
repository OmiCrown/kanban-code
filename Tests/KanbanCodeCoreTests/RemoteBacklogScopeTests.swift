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
