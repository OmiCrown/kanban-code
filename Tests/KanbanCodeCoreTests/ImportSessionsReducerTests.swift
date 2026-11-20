import Foundation
import Testing

@testable import KanbanCodeCore

@Suite("Importing sessions as cards")
struct ImportSessionsReducerTests {
    private func imported(_ sessionId: String, id: String? = nil) -> Link {
        Link(
            id: id ?? "card_\(sessionId)", name: "Session \(sessionId)", projectPath: "/work/app",
            source: .manual, sessionLink: SessionLink(sessionId: sessionId, sessionPath: "/p/\(sessionId).jsonl"))
    }

    private func persistCount(_ effects: [Effect]) -> (persist: Int, upsert: Int) {
        var persist = 0, upsert = 0
        for effect in effects {
            if case .persistLinks = effect { persist += 1 }
            if case .upsertLink = effect { upsert += 1 }
        }
        return (persist, upsert)
    }

    @Test("every chosen session becomes a card, with one write")
    func addsCardsWithOnePersist() {
        let state = AppState()
        let effects = Reducer.reduce(state: state, action: .importSessions([imported("s1"), imported("s2")]))

        #expect(state.links["card_s1"]?.sessionLink?.sessionId == "s1")
        #expect(state.links["card_s2"]?.sessionLink?.sessionId == "s2")
        let counts = persistCount(effects)
        #expect(counts.persist == 1)
        #expect(counts.upsert == 0)
    }

    @Test("a session another card already holds gets no second card")
    func skipsSessionAlreadyOnACard() {
        let state = AppState()
        state.links["old"] = imported("s1", id: "old")

        let effects = Reducer.reduce(state: state, action: .importSessions([imported("s1")]))

        #expect(state.links.count == 1)
        #expect(state.links["card_s1"] == nil)
        #expect(persistCount(effects).persist == 0)
    }

    @Test("the same session twice in one import makes one card")
    func skipsDuplicateInsideOneImport() {
        let state = AppState()
        _ = Reducer.reduce(
            state: state,
            action: .importSessions([imported("s1", id: "a"), imported("s1", id: "b")]))
        #expect(state.links.count == 1)
    }

    @Test("a deleted card's tombstone does not block the import")
    func tombstoneDoesNotBlock() {
        let state = AppState()
        var tomb = imported("s1", id: "gone")
        tomb.deletedAt = .now
        state.links["gone"] = tomb

        _ = Reducer.reduce(state: state, action: .importSessions([imported("s1")]))

        #expect(state.links["card_s1"] != nil)
    }

    @Test("an imported card is kept when discovery-only cards are archived")
    func importedCardSurvivesArchiveDiscoveryOnly() {
        let state = AppState()
        let candidate = ImportCandidate(
            sessionId: "s1", title: "fix login", projectPath: "/work/app", profilePath: "/h/.claude-A",
            transcriptPath: "/p/s1.jsonl", modifiedTime: .now, messageCount: 3, isRunning: false)
        let link = SessionImportPlanner.makeLink(candidate)
        _ = Reducer.reduce(state: state, action: .importSessions([link]))

        _ = Reducer.reduce(state: state, action: .archiveDiscoveryOnlyCards)

        #expect(state.links[link.id]?.manuallyArchived == false)
    }

    @Test("the user's choice clears an earlier deletion mark")
    func clearsDeletedMark() {
        let state = AppState()
        state.deletedSessionIds = ["s1", "other"]
        _ = Reducer.reduce(state: state, action: .importSessions([imported("s1")]))
        #expect(state.deletedSessionIds == ["other"])
    }
}
