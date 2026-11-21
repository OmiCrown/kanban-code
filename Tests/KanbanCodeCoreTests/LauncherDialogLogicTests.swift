import Testing
@testable import KanbanCodeCore

@Suite("Launcher dialog logic")
struct LauncherDialogLogicTests {
    private let launchers = [ClaudeLauncher.codemie]

    private func choice(
        edited: Bool = false, command: String = "", selected: String = "claude",
        assistant: CodingAssistant = .claude, remote: Bool = false
    ) -> String? {
        ClaudeLauncherResolver.choice(
            commandEdited: edited, command: command, selected: selected,
            assistant: assistant, runsRemotely: remote, launchers: launchers)
    }

    @Test("Codex gives no choice")
    func codexGivesNil() {
        #expect(choice(selected: "codemie-claude", assistant: .codex) == nil)
    }

    @Test("Gemini gives no choice")
    func geminiGivesNil() {
        #expect(choice(selected: "codemie-claude", assistant: .gemini) == nil)
    }

    @Test("a remote run gives no choice")
    func remoteGivesNil() {
        #expect(choice(selected: "codemie-claude", remote: true) == nil)
    }

    @Test("an edited command line is read for its binary")
    func editedCommand() {
        #expect(choice(edited: true, command: "codemie-claude --x", selected: "claude") == "codemie-claude")
    }

    @Test("an unedited command gives the selection")
    func uneditedGivesSelected() {
        #expect(choice(edited: false, command: "claude --x", selected: "codemie-claude") == "codemie-claude")
    }

    @Test("edited text with an unknown binary is plain")
    func editedUnknownBinary() {
        #expect(choice(edited: true, command: "other-tool --x", selected: "codemie-claude") == "claude")
    }

    @Test("a blank selection is plain")
    func blankSelectionIsPlain() {
        #expect(choice(selected: "  ") == "claude")
    }
}
