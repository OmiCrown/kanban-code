import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("Claude launcher editing")
struct ClaudeLauncherEditingTests {
    @Test func newLauncherTrimsAndGetsFreshId() throws {
        let a = try #require(ClaudeLauncherEditing.newLauncher(name: "  Work  ", command: " my-claude --flag "))
        let b = try #require(ClaudeLauncherEditing.newLauncher(name: "Work", command: "my-claude --flag"))
        #expect(a.name == "Work")
        #expect(a.command == "my-claude --flag")
        #expect(!a.id.isEmpty && a.id != b.id)
        #expect(UUID(uuidString: a.id) != nil)
    }

    @Test func newLauncherRejectsEmptyCommand() {
        #expect(ClaudeLauncherEditing.newLauncher(name: "x", command: "") == nil)
        #expect(ClaudeLauncherEditing.newLauncher(name: "x", command: " \n ") == nil)
    }

    @Test func emptyNameFallsBackToCommand() throws {
        let launcher = try #require(ClaudeLauncherEditing.newLauncher(name: " ", command: "tool"))
        #expect(launcher.name == "tool")
    }

    @Test func renameKeepsIdAndProfileLink() {
        let profile = ClaudeProfile(path: "/h/.claude-x", projectRoots: ["/r"], launcherId: "codemie", home: "/h")
        let renamed = ClaudeLauncherEditing.edited(.codemie, name: " Gateway ", command: " codemie-claude ")
        #expect(renamed.id == "codemie")
        #expect(renamed.name == "Gateway")
        #expect(ClaudeLauncherResolver.defaultCommand(
            forProjectPath: "/r/app", profiles: [profile], launchers: [renamed]) == "codemie-claude")
    }

    @Test func editKeepsOldValueForEmptyField() {
        let result = ClaudeLauncherEditing.edited(.codemie, name: "", command: "  ")
        #expect(result == .codemie)
    }

    @Test func removedLauncherLeavesIdDanglingAndDefaultPlain() {
        let profile = ClaudeProfile(path: "/h/.claude-x", projectRoots: ["/r"], launcherId: "codemie", home: "/h")
        #expect(ClaudeLauncherResolver.defaultCommand(
            forProjectPath: "/r/app", profiles: [profile], launchers: []) == "claude")
        #expect(profile.launcherId == "codemie")
    }

    @Test func cleanedDropsEmptyCommandsTrimsAndFixesIds() {
        let list = [
            ClaudeLauncher(id: "a", name: " A ", command: " cmd-a "),
            ClaudeLauncher(id: "b", name: "B", command: "  "),
            ClaudeLauncher(id: "a", name: "", command: "cmd-c"),
            ClaudeLauncher(id: "", name: "D", command: "cmd d --x"),
        ]
        let result = ClaudeLauncherEditing.cleaned(list)
        #expect(result.map(\.command) == ["cmd-a", "cmd-c", "cmd d --x"])
        #expect(result.map(\.name) == ["A", "cmd-c", "D"])
        #expect(result[0].id == "a")
        #expect(Set(result.map(\.id)).count == 3)
        #expect(!result.contains { $0.id.isEmpty })
    }

    @Test func cleanedKeepsAValidListUnchanged() {
        #expect(ClaudeLauncherEditing.cleaned([.codemie]) == [.codemie])
    }

    @Test func popupSelectionShowsPlainForMissingLauncher() {
        #expect(ClaudeLauncherEditing.popupSelection(launcherId: nil, launchers: [.codemie]) == nil)
        #expect(ClaudeLauncherEditing.popupSelection(launcherId: "codemie", launchers: [.codemie]) == "codemie")
        #expect(ClaudeLauncherEditing.popupSelection(launcherId: "gone", launchers: [.codemie]) == nil)
        #expect(ClaudeLauncherEditing.popupSelection(launcherId: "codemie", launchers: []) == nil)
    }
}
