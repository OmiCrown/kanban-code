import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ProfileBoardFilter")
struct ProfileBoardFilterTests {
    private let home = "/Users/test"

    private func profile(_ name: String, enabled: Bool = true) -> ClaudeProfile {
        ClaudeProfile(path: "\(home)/\(name)", enabled: enabled, home: home)
    }

    /// A card whose session transcript lives in `\(home)/<profileDir>/projects/-p/<id>.jsonl`.
    private func addCard(_ state: inout AppState, id: String, profileDir: String, modified: Date = .now) {
        let sessionId = "sess-\(id)"
        state.links[id] = Link(
            id: id, name: id, projectPath: "/p", column: .backlog, source: .manual,
            sessionLink: SessionLink(sessionId: sessionId))
        state.sessions[sessionId] = Session(
            id: sessionId, messageCount: 2, modifiedTime: modified,
            jsonlPath: "\(home)/\(profileDir)/projects/-p/\(sessionId).jsonl")
    }

    private func visibleIds(_ state: inout AppState) -> Set<String> {
        state.rebuildCards()
        return Set(state.filteredCards.map(\.id))
    }

    @Test func cardTakesProfileOfNewestSession() {
        var state = AppState()
        // The card's link points at the newest session, which sits in profile B.
        state.links["c"] = Link(
            id: "c", name: "c", projectPath: "/p", column: .backlog, source: .manual,
            sessionLink: SessionLink(sessionId: "new"))
        state.sessions["old"] = Session(
            id: "old", messageCount: 1, modifiedTime: .now.addingTimeInterval(-100),
            jsonlPath: "\(home)/.claude/projects/-p/old.jsonl")
        state.sessions["new"] = Session(
            id: "new", messageCount: 1, modifiedTime: .now,
            jsonlPath: "\(home)/.claude-B/projects/-p/new.jsonl")
        state.rebuildCards()
        #expect(state.cards.first?.profileConfigDirectory == "\(home)/.claude-B")
    }

    @Test func cardFallsBackToLinkPath() {
        var state = AppState()
        state.links["c"] = Link(
            id: "c", name: "c", projectPath: "/p", column: .backlog, source: .manual,
            sessionLink: SessionLink(sessionId: "x", sessionPath: "\(home)/.claude-B/projects/-p/x.jsonl"))
        state.rebuildCards()
        #expect(state.cards.first?.profileConfigDirectory == "\(home)/.claude-B")
    }

    @Test func filterByProfile() {
        var state = AppState()
        state.profiles = [profile(".claude"), profile(".claude-A"), profile(".claude-B")]
        addCard(&state, id: "a", profileDir: ".claude-A")
        addCard(&state, id: "b", profileDir: ".claude-B")
        #expect(visibleIds(&state) == ["a", "b"])
        state.selectedProfilePath = "\(home)/.claude-A"
        #expect(visibleIds(&state) == ["a"])
        state.selectedProfilePath = nil
        #expect(visibleIds(&state) == ["a", "b"])
    }

    @Test func disabledProfileCardsHidden() {
        var state = AppState()
        state.profiles = [profile(".claude"), profile(".claude-A"), profile(".claude-B", enabled: false)]
        addCard(&state, id: "a", profileDir: ".claude-A")
        addCard(&state, id: "b", profileDir: ".claude-B")
        #expect(visibleIds(&state) == ["a"])
    }

    @Test func reEnablingBringsThemBack() {
        var state = AppState()
        state.profiles = [profile(".claude"), profile(".claude-B", enabled: false)]
        addCard(&state, id: "b", profileDir: ".claude-B")
        #expect(visibleIds(&state).isEmpty)
        state.profiles = [profile(".claude"), profile(".claude-B", enabled: true)]
        #expect(visibleIds(&state) == ["b"])
    }

    @Test func unknownProfileCardsStay() {
        var state = AppState()
        state.profiles = [profile(".claude"), profile(".claude-A", enabled: false)]
        addCard(&state, id: "x", profileDir: ".claude-unregistered")
        state.links["nopath"] = Link(id: "nopath", name: "n", projectPath: "/p", column: .backlog, source: .manual)
        #expect(visibleIds(&state) == ["x", "nopath"])
    }

    @Test func singleProfileShowsEverything() {
        var state = AppState()
        state.profiles = [profile(".claude")]
        addCard(&state, id: "a", profileDir: ".claude")
        #expect(visibleIds(&state) == ["a"])
    }

    @Test func settingProfilesDropsAStaleSelection() {
        var state = AppState()
        state.profiles = [profile(".claude"), profile(".claude-A")]
        _ = Reducer.reduce(state: &state, action: .setSelectedProfile("\(home)/.claude-A"))
        #expect(state.selectedProfilePath == "\(home)/.claude-A")
        _ = Reducer.reduce(state: &state, action: .setProfiles([profile(".claude"), profile(".claude-A", enabled: false)]))
        #expect(state.selectedProfilePath == nil)
    }
}
