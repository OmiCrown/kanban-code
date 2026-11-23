import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import KanbanCodeRemoteKit
import Synchronization
import Testing

@testable import KanbanCodeCore

/// The Mac's Tailscale addresses as the server sees them. A test Mac has none,
/// so `::1` plays one: it is bindable, it is not `127.0.0.1`, and a request to
/// it reaches the server only while the server listens on it.
final class FakeTailscale: Sendable {
    private let list: Mutex<[String]>

    init(_ addresses: [String]) {
        list = Mutex(addresses)
    }

    func set(_ addresses: [String]) {
        list.withLock { $0 = addresses }
    }

    var addresses: [String] { list.withLock { $0 } }
}

/// The status of GET `path` on `host:port` through a session of its own, or
/// nil when the connection fails (refused, closed, timed out).
private func status(host: String, port: Int, path: String = "/v1/health") async -> Int? {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 3
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    guard let url = URL(string: "http://\(host):\(port)\(path)"),
          let (_, response) = try? await session.data(from: url) else { return nil }
    return (response as? HTTPURLResponse)?.statusCode
}

private func makeFixture(_ mode: RemoteListenMode, tailscale: FakeTailscale) async throws -> (RemoteServerFixture, RemoteListenModeBox) {
    let box = RemoteListenModeBox(mode)
    let fixture = try await RemoteServerFixture(bindAddresses: { box.bindAddresses(tailscale: { tailscale.addresses }) })
    return (fixture, box)
}

@Suite("Remote listen mode on a running server")
struct RemoteListenModeServerTests {
    @Test("this Mac only refuses a request on the Tailscale address")
    func thisMacOnlyRefusesTheTailscaleAddress() async throws {
        let (f, _) = try await makeFixture(.thisMac, tailscale: FakeTailscale(["::1"]))
        defer { f.shutdown() }
        #expect(f.server.listeningAddresses == ["127.0.0.1"])
        #expect(await status(host: "[::1]", port: f.server.port) == nil)
        #expect(await status(host: "127.0.0.1", port: f.server.port) == 200)
    }

    @Test("also Tailscale serves a request on the Tailscale address")
    func tailscaleModeServesIt() async throws {
        let (f, _) = try await makeFixture(.tailscale, tailscale: FakeTailscale(["::1"]))
        defer { f.shutdown() }
        await f.server.reconcile()
        #expect(f.server.listeningAddresses == ["127.0.0.1", "::1"])
        #expect(await status(host: "[::1]", port: f.server.port) == 200)
    }

    @Test("switching to this Mac only drops the listener and keeps the port")
    func switchingToThisMacDropsTheListener() async throws {
        let (f, box) = try await makeFixture(.tailscale, tailscale: FakeTailscale(["::1"]))
        defer { f.shutdown() }
        let port = f.server.port
        #expect(f.server.listeningAddresses == ["127.0.0.1", "::1"])

        box.set(.thisMac)
        await f.server.reconcile()

        #expect(f.server.listeningAddresses == ["127.0.0.1"])
        #expect(f.server.port == port)
        #expect(await status(host: "[::1]", port: port) == nil)
        #expect(await status(host: "127.0.0.1", port: port) == 200)
    }

    @Test("switching back to also Tailscale listens on the address again")
    func switchingBackAddsItAgain() async throws {
        let (f, box) = try await makeFixture(.thisMac, tailscale: FakeTailscale(["::1"]))
        defer { f.shutdown() }
        #expect(f.server.listeningAddresses == ["127.0.0.1"])

        box.set(.tailscale)
        await f.server.reconcile()

        #expect(f.server.listeningAddresses == ["127.0.0.1", "::1"])
        #expect(await status(host: "[::1]", port: f.server.port) == 200)
    }

    @Test("Tailscale coming up after the server started is bound at the next reconcile")
    func tailscaleComingUpLater() async throws {
        let tailscale = FakeTailscale([])
        let (f, _) = try await makeFixture(.tailscale, tailscale: tailscale)
        defer { f.shutdown() }
        #expect(f.server.listeningAddresses == ["127.0.0.1"])

        tailscale.set(["::1"])
        await f.server.reconcile()

        #expect(f.server.listeningAddresses == ["127.0.0.1", "::1"])
    }

    #if !canImport(FoundationNetworking)
    @Test("switching to this Mac only closes a socket that came in on the Tailscale address and not the loopback one")
    func switchingClosesOpenTailnetConnections() async throws {
        let (f, box) = try await makeFixture(.tailscale, tailscale: FakeTailscale(["::1"]))
        defer { f.shutdown() }
        var request = URLRequest(url: URL(string: "ws://[::1]:\(f.server.port)/v1/events")!)
        request.setValue("Bearer \(f.fullToken)", forHTTPHeaderField: "Authorization")
        let tailnetSocket = f.session.webSocketTask(with: request)
        tailnetSocket.resume()
        let loopbackSocket = f.webSocket("/v1/events", token: f.fullToken)
        defer {
            tailnetSocket.cancel(with: .normalClosure, reason: nil)
            loopbackSocket.cancel(with: .normalClosure, reason: nil)
        }
        _ = try await withTimeout(5) { try await tailnetSocket.receive() }
        _ = try await withTimeout(5) { try await loopbackSocket.receive() }

        box.set(.thisMac)
        await f.server.reconcile()

        var tailnetClosed = false
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if (try? await withTimeout(1) { try await tailnetSocket.receive() }) == nil {
                tailnetClosed = true
                break
            }
        }
        #expect(tailnetClosed, "the socket on the Tailscale address is still open")
        #expect((try? await withTimeout(3) { try await loopbackSocket.receive() }) != nil, "the loopback socket was closed")
    }
    #endif
}
