import Foundation
import Testing

@testable import KanbanCodeCore

/// What Claude shows the first time `--dangerously-skip-permissions` runs in a
/// config folder. Its selector `❯` looks like the input prompt, and the
/// highlighted answer is "No, exit".
private let bypassDialog = """
 WARNING: Claude Code running in Bypass Permissions mode

 In Bypass Permissions mode, Claude Code will not ask for your approval before running potentially
 dangerous commands.

 By proceeding, you accept all responsibility for actions taken while running in Bypass Permissions
 mode.

 https://code.claude.com/docs/en/security

 ❯ No, exit
   Yes, I accept

 Enter to confirm · Esc to cancel
"""

/// A tmux transport whose pane shows `pane`, and that counts Enter presses.
private final class FixedPaneTransport: TmuxTransport, @unchecked Sendable {
    let pane: String
    private let lock = NSLock()
    private var _calls: [[String]] = []
    init(pane: String) { self.pane = pane }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }
    var enterPresses: Int { calls.filter { $0.first == "send-keys" && $0.last == "Enter" }.count }

    func run(_ arguments: [String], timeout: TimeInterval) async throws -> ShellCommand.Result {
        record(arguments)
        return ShellCommand.Result(
            exitCode: 0, stdout: arguments.first == "capture-pane" ? pane : "", stderr: "")
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

@Suite("Claude's Bypass Permissions consent dialog")
struct BypassConsentTests {
    @Test("the dialog is recognised, a running session and a plain prompt are not")
    func detection() {
        #expect(PaneOutputParser.claudeAsksBypassConsent(bypassDialog))
        #expect(!PaneOutputParser.claudeAsksBypassConsent("❯ \n  ⏵⏵ bypass permissions on (shift+tab to cycle)"))
        #expect(!PaneOutputParser.claudeAsksBypassConsent("❯ fix the bug"))
        #expect(!PaneOutputParser.claudeAsksBypassConsent(""))
    }

    @Test("the dialog's selector is not an input prompt")
    func dialogIsNotReady() {
        #expect(!PaneOutputParser.isReady(bypassDialog, assistant: .claude))
        #expect(PaneOutputParser.isReady("────\n❯ \n────", assistant: .claude))
    }

    @Test("waiting for Claude reports the dialog instead of calling it ready or timing out")
    func waitForReadyReportsDialog() async {
        let mock = ImageSenderTests.MockTmux()
        mock.capturedPaneOutputs = [bypassDialog]
        let sender = ImageSender(tmux: mock)
        do {
            try await sender.waitForReady(
                sessionName: "s", pollInterval: .milliseconds(10),
                timeout: .seconds(5), consentTimeout: .milliseconds(80))
            Issue.record("waitForReady returned although the dialog is still up")
        } catch let error as ImageSendError {
            guard case .needsConfirmation = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            #expect(error.errorDescription?.contains("Yes, I accept") == true)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("waiting goes on once the dialog is answered")
    func waitForReadyContinuesAfterAnswer() async throws {
        let mock = ImageSenderTests.MockTmux()
        mock.capturedPaneOutputs = [bypassDialog, bypassDialog, "────\n❯ \n────"]
        let sender = ImageSender(tmux: mock)
        try await sender.waitForReady(
            sessionName: "s", pollInterval: .milliseconds(10),
            timeout: .seconds(5), consentTimeout: .seconds(5))
        #expect(mock.captureCallCount == 3)
    }

    @Test("no Enter is pressed while the dialog is up: it would pick \"No, exit\"")
    func noEnterOnDialog() async {
        let transport = FixedPaneTransport(pane: bypassDialog)
        let tmux = TmuxAdapter(transport: transport)

        await #expect(throws: TmuxError.self) {
            try await tmux.pastePrompt(to: "claude-1", text: "hello", timeout: .seconds(2), abortIf: nil)
        }
        await #expect(throws: TmuxError.self) {
            try await tmux.sendPrompt(to: "claude-1", text: "hello")
        }
        #expect(transport.enterPresses == 0)
    }

    @Test("the error says what to do")
    func errorText() {
        let text = TmuxError.needsConfirmation(sessionName: "card-1").errorDescription ?? ""
        #expect(text.contains("Yes, I accept"))
        #expect(text.contains("card-1"))
    }
}
