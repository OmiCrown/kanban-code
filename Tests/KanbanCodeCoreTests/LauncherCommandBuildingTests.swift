import Testing
import Foundation
@testable import KanbanCodeCore

private final class CommandCapturingTmux: TmuxManagerPort, @unchecked Sendable {
    var commands: [String] = []

    func createSession(name: String, path: String, command: String?) async throws {
        commands.append(command ?? "")
    }
    func listSessions() async throws -> [TmuxSession] { [] }
    func killSession(name: String) async throws {}
    func findSessionForWorktree(sessions: [TmuxSession], worktreePath: String, branch: String?) -> TmuxSession? { nil }
    func sendPrompt(to sessionName: String, text: String) async throws {}
    func pastePrompt(to sessionName: String, text: String) async throws {}
    func pasteText(to sessionName: String, text: String) async throws {}
    func submitPrompt(to sessionName: String) async throws {}
    func capturePane(sessionName: String) async throws -> String { "" }
    func sendBracketedPaste(to sessionName: String) async throws {}
    func isAvailable() async -> Bool { true }
}

@Suite("Launcher command building")
struct LauncherCommandBuildingTests {

    @Test("A launch command takes the other binary and keeps the flags")
    func launchReplacesBinary() {
        let cmd = CodingAssistant.claude.launchCommand(
            skipPermissions: true, worktreeName: "todo", binaryOverride: "codemie-claude")
        #expect(cmd == "codemie-claude --dangerously-skip-permissions --worktree todo")
    }

    @Test("A resume command takes the other binary and keeps the flags")
    func resumeReplacesBinary() {
        let cmd = CodingAssistant.claude.resumeCommand(
            sessionId: "abc", skipPermissions: true, binaryOverride: "codemie-claude")
        #expect(cmd == "codemie-claude --dangerously-skip-permissions --resume abc")
    }

    @Test("No override leaves both commands as they were")
    func nilOverrideIsUnchanged() {
        #expect(
            CodingAssistant.claude.launchCommand(
                skipPermissions: true, worktreeName: "todo", binaryOverride: nil)
                == "claude --dangerously-skip-permissions --worktree todo")
        #expect(
            CodingAssistant.claude.resumeCommand(
                sessionId: "abc", skipPermissions: true, binaryOverride: nil)
                == "claude --dangerously-skip-permissions --resume abc")
    }

    @Test("Codex and Gemini ignore the override")
    func codexAndGeminiIgnoreIt() {
        #expect(
            CodingAssistant.codex.launchCommand(
                skipPermissions: true, worktreeName: nil, binaryOverride: "codemie-claude")
                .hasPrefix("codex"))
        #expect(
            CodingAssistant.codex.resumeCommand(
                sessionId: "abc", skipPermissions: true, binaryOverride: "codemie-claude")
                .hasPrefix("codex"))
        #expect(
            CodingAssistant.gemini.launchCommand(
                skipPermissions: true, worktreeName: nil, binaryOverride: "codemie-claude")
                .hasPrefix("gemini"))
        #expect(
            CodingAssistant.gemini.resumeCommand(
                sessionId: "abc", skipPermissions: true, binaryOverride: "codemie-claude")
                .hasPrefix("gemini"))
    }

    @Test("A service launcher still wraps the override where claude stood")
    func serviceLauncherStillWraps() {
        let service = APIService(
            name: "Ollama", assistant: .claude,
            launcherPrefix: "ollama launch", modelFlag: "qwen3")
        let launch = CodingAssistant.claude.launchCommand(
            skipPermissions: true, worktreeName: nil, service: service,
            binaryOverride: "codemie-claude")
        #expect(launch == "ollama launch codemie-claude --model qwen3 -- --dangerously-skip-permissions")
        let resume = CodingAssistant.claude.resumeCommand(
            sessionId: "abc", skipPermissions: true, service: service,
            binaryOverride: "codemie-claude")
        #expect(resume == "ollama launch codemie-claude --model qwen3 -- --dangerously-skip-permissions --resume abc")
    }

    @Test("The wrapper template wraps the command with the override")
    func wrapperTemplateWrapsOverride() {
        let built = CodingAssistant.claude.launchCommand(
            skipPermissions: false, worktreeName: nil, binaryOverride: "codemie-claude")
        let wrapped = CodingAssistant.applyCommandTemplate(built, template: "langwatch")
        #expect(wrapped.hasPrefix("langwatch codemie-claude"))
    }

    @Test("LaunchSession puts the launcher command into the tmux command")
    func launchSessionLaunch() async throws {
        let tmux = CommandCapturingTmux()
        let launcher = LaunchSession(tmux: tmux)
        _ = try await launcher.launch(
            sessionName: "card", projectPath: "/tmp/project", prompt: "hi",
            worktreeName: nil, shellOverride: nil, skipPermissions: true, launcherCommand: "codemie-claude")
        #expect(tmux.commands.last?.contains("&& codemie-claude ") == true)
        #expect(tmux.commands.last?.contains("&& claude ") == false)
    }

    @Test("LaunchSession keeps claude when the launcher command is nil")
    func launchSessionLaunchDefault() async throws {
        let tmux = CommandCapturingTmux()
        let launcher = LaunchSession(tmux: tmux)
        _ = try await launcher.launch(
            sessionName: "card", projectPath: "/tmp/project", prompt: "hi",
            worktreeName: nil, shellOverride: nil, skipPermissions: true, launcherCommand: nil)
        #expect(tmux.commands.last?.contains("&& claude ") == true)
    }

    @Test("LaunchSession resumes with the launcher command")
    func launchSessionResume() async throws {
        let tmux = CommandCapturingTmux()
        let launcher = LaunchSession(tmux: tmux)
        _ = try await launcher.resume(
            sessionId: "abcdef12-0000", projectPath: "/tmp/project", shellOverride: nil,
            skipPermissions: true, launcherCommand: "codemie-claude")
        #expect(tmux.commands.last?.contains("&& codemie-claude ") == true)
        #expect(tmux.commands.last?.contains("&& claude ") == false)
    }

    @Test("LaunchSession resumes with claude when the launcher command is nil")
    func launchSessionResumeDefault() async throws {
        let tmux = CommandCapturingTmux()
        let launcher = LaunchSession(tmux: tmux)
        _ = try await launcher.resume(
            sessionId: "abcdef12-0000", projectPath: "/tmp/project", shellOverride: nil,
            skipPermissions: true, launcherCommand: nil)
        #expect(tmux.commands.last?.contains("&& claude ") == true)
    }
}
