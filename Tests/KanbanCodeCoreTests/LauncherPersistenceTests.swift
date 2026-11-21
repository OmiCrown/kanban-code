import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("Launcher persistence")
struct LauncherPersistenceTests {
    private func stateWith(_ links: [Link]) -> AppState {
        var state = AppState()
        for link in links { state.links[link.id] = link }
        state.rebuildCards()
        return state
    }

    // MARK: - Link

    @Test func oldLinkJsonDecodesWithNilLauncher() throws {
        let json = #"{"id":"card_old","name":"Old"}"#
        let link = try JSONDecoder().decode(Link.self, from: Data(json.utf8))
        #expect(link.launcherCommand == nil)
    }

    @Test func launcherCommandRoundTrips() throws {
        let link = Link(id: "card_x", launcherCommand: "codemie-claude")
        let back = try JSONDecoder().decode(Link.self, from: JSONEncoder().encode(link))
        #expect(back.launcherCommand == "codemie-claude")
    }

    @Test func nilLauncherIsNotEncoded() throws {
        let data = try JSONEncoder().encode(Link(id: "card_x"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["launcherCommand"] == nil)
    }

    // MARK: - Settings

    @Test func oldSettingsGetSeededOnce() throws {
        let fresh = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(fresh.claudeLaunchers == [.codemie])
        #expect(fresh.launchersSeeded == true)

        // The user deleted the seed: it stays deleted after the next load.
        let emptied = try JSONDecoder().decode(
            Settings.self, from: Data(#"{"claudeLaunchers":[],"launchersSeeded":true}"#.utf8))
        #expect(emptied.claudeLaunchers.isEmpty)
        #expect(emptied.launchersSeeded == true)
    }

    @Test func seededSettingsRoundTrip() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(back.claudeLaunchers == [.codemie])
        #expect(back.launchersSeeded == true)
    }

    @Test func existingLaunchersAreNotReplacedBySeed() throws {
        let json = #"{"claudeLaunchers":[{"id":"mine","name":"Mine","command":"my-claude"}]}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.claudeLaunchers.map(\.id) == ["mine"])
        #expect(settings.launchersSeeded == true)
    }

    @Test func badLauncherValueDoesNotWipeSettings() throws {
        let json = #"{"hasCompletedOnboarding":true,"claudeLaunchers":"nonsense"}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.hasCompletedOnboarding == true)
        #expect(settings.claudeLaunchers == [.codemie])
    }

    @Test func initDefaultsAreEmptyAndUnseeded() {
        let settings = Settings()
        #expect(settings.claudeLaunchers.isEmpty)
        #expect(settings.launchersSeeded == false)
    }

    // MARK: - Reducer

    @Test func reducerSetsAndClears() {
        var state = stateWith([Link(id: "card_a")])

        let set = Reducer.reduce(state: &state, action: .setLauncherCommand(cardId: "card_a", command: "codemie-claude"))
        #expect(state.links["card_a"]?.launcherCommand == "codemie-claude")
        #expect(set.count == 1)
        if case .upsertLink(let link) = set.first { #expect(link.launcherCommand == "codemie-claude") }
        else { Issue.record("expected upsertLink, got \(set)") }

        let same = Reducer.reduce(state: &state, action: .setLauncherCommand(cardId: "card_a", command: "codemie-claude"))
        #expect(same.isEmpty)

        let cleared = Reducer.reduce(state: &state, action: .setLauncherCommand(cardId: "card_a", command: nil))
        #expect(state.links["card_a"]?.launcherCommand == nil)
        #expect(cleared.count == 1)

        let unknown = Reducer.reduce(state: &state, action: .setLauncherCommand(cardId: "nope", command: "x"))
        #expect(unknown.isEmpty)
    }

    @Test func migrationToAnotherAssistantClearsIt() {
        var link = Link(
            id: "card_mig",
            sessionLink: SessionLink(sessionId: "old", sessionPath: "/old.jsonl"),
            assistant: .claude
        )
        link.launcherCommand = "codemie-claude"
        var state = stateWith([link])

        _ = Reducer.reduce(state: &state, action: .migrateSession(
            cardId: link.id, newAssistant: .codex, newSessionId: "new", newSessionPath: "/new.jsonl"))

        #expect(state.links[link.id]?.assistant == .codex)
        #expect(state.links[link.id]?.launcherCommand == nil)
    }

    @Test func reconcilerKeepsIt() {
        var existing = Link(id: "card_rec", name: "Rec")
        existing.launcherCommand = "codemie-claude"
        var state = stateWith([existing])
        let rebuilt = Link(id: "card_rec", name: "Rec")

        _ = Reducer.reduce(state: &state, action: .reconciled(ReconciliationResult(
            links: [rebuilt], sessions: [], activityMap: [:], tmuxSessions: [])))

        #expect(state.links["card_rec"]?.launcherCommand == "codemie-claude")
    }

    // MARK: - LinkSync

    @Test func launcherCommandIsAnOwnedField() {
        #expect(LinkSync.ownedFieldNames.contains("launcherCommand"))
        #expect(!LinkSync.sharedFieldNames.contains("launcherCommand"))
    }

    @Test func copyOwnedCarriesLauncherCommand() {
        var peer = Link(id: "card_s")
        peer.launcherCommand = "codemie-claude"
        var mine = Link(id: "card_s")
        #expect(!LinkSync.ownedEqual(mine, peer))
        LinkSync.copyOwned(from: peer, to: &mine)
        #expect(mine.launcherCommand == "codemie-claude")
        #expect(LinkSync.ownedEqual(mine, peer))
    }
}
