import Foundation
import Testing

@testable import KanbanCodeCore

/// Records tmux calls; `has-session` says the session does not exist yet.
private final class RecordingTransport: TmuxTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }
    func run(_ arguments: [String], timeout: TimeInterval) async throws -> ShellCommand.Result {
        record(arguments)
        return ShellCommand.Result(exitCode: arguments.first == "has-session" ? 1 : 0, stdout: "", stderr: "")
    }
    private func record(_ arguments: [String]) {
        lock.lock()
        defer { lock.unlock() }
        _calls.append(arguments)
    }
    func writeTempFile(name: String, contents: String) async throws -> String { "/fake/\(name)" }
    func removeTempFile(_ path: String) async {}
    func isAvailable() async -> Bool { true }
}

@Suite("tmux status line of a card session")
struct TmuxStatusLineTests {
    @Test("a new session hides tmux's own status line: the card has its own header")
    func statusLineHidden() async throws {
        let transport = RecordingTransport()
        try await TmuxAdapter(transport: transport)
            .createSession(name: "card-1", path: "/tmp", command: nil)

        let calls = transport.calls
        let created = try #require(calls.firstIndex { $0.first == "new-session" })
        let hidden = try #require(calls.firstIndex { $0 == ["set-option", "-t", "card-1", "status", "off"] })
        #expect(hidden > created)
    }

    @Test("an existing session is left as it is")
    func existingSessionUntouched() async throws {
        final class Existing: TmuxTransport, @unchecked Sendable {
            func run(_ arguments: [String], timeout: TimeInterval) async throws -> ShellCommand.Result {
                ShellCommand.Result(exitCode: 0, stdout: "", stderr: "")
            }
            func writeTempFile(name: String, contents: String) async throws -> String { "" }
            func removeTempFile(_ path: String) async {}
            func isAvailable() async -> Bool { true }
        }
        try await TmuxAdapter(transport: Existing()).createSession(name: "card-1", path: "/tmp", command: nil)
    }
}
