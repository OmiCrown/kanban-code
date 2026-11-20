import Foundation
import KanbanCodeCore
import Observation

/// The chat/terminal choice of each card, kept in `UserDefaults`.
///
/// `preferChatView` (the old, shared key) stays as the default for a card that
/// has no choice yet, so the board looks as it did before the choice became
/// per card.
@MainActor
@Observable
final class ChatViewPreferences {
    static let shared = ChatViewPreferences()

    private static let choicesKey = "chatViewByCard"
    static let defaultKey = "preferChatView"

    private var choices: ChatViewChoices

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.choicesKey),
           let stored = try? JSONDecoder().decode(ChatViewChoices.self, from: data) {
            choices = stored
        } else {
            choices = ChatViewChoices()
        }
    }

    func prefersChat(cardId: String) -> Bool {
        choices.prefersChat(cardId: cardId, default: UserDefaults.standard.bool(forKey: Self.defaultKey))
    }

    func setPrefersChat(_ chat: Bool, cardId: String) {
        choices.set(chat, cardId: cardId)
        save()
    }

    /// Sets the default and drops every card's own choice.
    func setDefault(_ chat: Bool) {
        UserDefaults.standard.set(chat, forKey: Self.defaultKey)
        choices.reset()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(choices) {
            UserDefaults.standard.set(data, forKey: Self.choicesKey)
        }
    }
}
