import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ChatViewChoices")
struct ChatViewChoicesTests {
    @Test("Two cards: switching one leaves the other on its view")
    func choiceIsPerCard() {
        var choices = ChatViewChoices()
        choices.set(true, cardId: "a")
        #expect(choices.prefersChat(cardId: "a", default: false))
        #expect(!choices.prefersChat(cardId: "b", default: false))
    }

    @Test("A card with no choice follows the default")
    func defaultApplies() {
        let choices = ChatViewChoices()
        #expect(choices.prefersChat(cardId: "new", default: true))
        #expect(!choices.prefersChat(cardId: "new", default: false))
    }

    @Test("A choice holds against the default, in both directions")
    func choiceBeatsDefault() {
        var choices = ChatViewChoices()
        choices.set(false, cardId: "a")
        choices.set(true, cardId: "b")
        #expect(!choices.prefersChat(cardId: "a", default: true))
        #expect(choices.prefersChat(cardId: "b", default: false))
    }

    @Test("Reset gives every card the default again")
    func resetFollowsDefault() {
        var choices = ChatViewChoices()
        choices.set(true, cardId: "a")
        choices.reset()
        #expect(choices.isEmpty)
        #expect(!choices.prefersChat(cardId: "a", default: false))
    }

    @Test("The choices survive an encode and a decode")
    func roundTrip() throws {
        var choices = ChatViewChoices()
        choices.set(true, cardId: "a")
        choices.set(false, cardId: "b")
        let back = try JSONDecoder().decode(ChatViewChoices.self, from: JSONEncoder().encode(choices))
        #expect(back == choices)
        #expect(back.prefersChat(cardId: "a", default: false))
        #expect(!back.prefersChat(cardId: "b", default: true))
    }
}
