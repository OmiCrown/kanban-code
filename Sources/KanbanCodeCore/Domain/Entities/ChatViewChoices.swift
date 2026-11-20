import Foundation

/// Which cards show the chat instead of the terminal, one choice per card.
///
/// A card with no choice follows the default the caller passes (the value the
/// app kept before the choice was per card), so switching one card to the chat
/// leaves the others as they were.
public struct ChatViewChoices: Codable, Equatable, Sendable {
    private var byCard: [String: Bool] = [:]

    public init() {}

    public func prefersChat(cardId: String, default fallback: Bool) -> Bool {
        byCard[cardId] ?? fallback
    }

    public mutating func set(_ chat: Bool, cardId: String) {
        byCard[cardId] = chat
    }

    /// Drops every choice, so each card follows the default again.
    public mutating func reset() {
        byCard.removeAll()
    }

    public var isEmpty: Bool { byCard.isEmpty }
}
