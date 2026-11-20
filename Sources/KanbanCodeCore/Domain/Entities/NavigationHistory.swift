import Foundation

/// A place the board can show in its detail drawer, as the back/forward
/// arrows remember it.
public enum DrawerNavigationTarget: Equatable, Sendable {
    case card(String)
    case channel(String)
    case dm(ChannelParticipant)

    public init?(_ drawer: Drawer) {
        switch drawer {
        case .none: return nil
        case .card(let id): self = .card(id)
        case .channel(let name): self = .channel(name)
        case .dm(let participant): self = .dm(participant)
        }
    }
}

/// The places the user visited, with a cursor on the one being shown.
///
/// One list and a cursor, not a back stack and a forward stack with a flag
/// that says "ignore the next change": a selection that the arrows made is
/// recognised because it equals the entry under the cursor, so no flag can be
/// consumed by the wrong change (a drawer that passes through `.none`, or two
/// changes in one pass) and clear what lies ahead.
public struct NavigationHistory: Equatable, Sendable {
    public static let limit = 100

    public private(set) var entries: [DrawerNavigationTarget] = []
    /// The index of the entry being shown, or -1 before the first visit.
    public private(set) var cursor = -1

    public init() {}

    /// The drawer now shows `target` (nil: closed). A place that is already
    /// under the cursor changes nothing, which is what an arrow press makes.
    /// Closing the drawer changes nothing either: the entry stays, so the
    /// arrows can come back to it.
    public mutating func visit(_ target: DrawerNavigationTarget?) {
        guard let target else { return }
        if cursor >= 0, entries[cursor] == target { return }
        entries.removeSubrange((cursor + 1)...)
        entries.append(target)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        cursor = entries.count - 1
    }

    /// The nearest earlier entry that `isAvailable` accepts, without moving.
    public func backTarget(
        isAvailable: (DrawerNavigationTarget) -> Bool
    ) -> (target: DrawerNavigationTarget, index: Int)? {
        var i = cursor - 1
        while i >= 0 {
            if isAvailable(entries[i]) { return (entries[i], i) }
            i -= 1
        }
        return nil
    }

    /// The nearest later entry that `isAvailable` accepts, without moving.
    public func forwardTarget(
        isAvailable: (DrawerNavigationTarget) -> Bool
    ) -> (target: DrawerNavigationTarget, index: Int)? {
        var i = cursor + 1
        while i < entries.count {
            if isAvailable(entries[i]) { return (entries[i], i) }
            i += 1
        }
        return nil
    }

    /// Moves the cursor to the entry `backTarget`/`forwardTarget` returned.
    public mutating func move(to index: Int) {
        guard entries.indices.contains(index) else { return }
        cursor = index
    }

    @discardableResult
    public mutating func goBack(isAvailable: (DrawerNavigationTarget) -> Bool) -> DrawerNavigationTarget? {
        guard let found = backTarget(isAvailable: isAvailable) else { return nil }
        cursor = found.index
        return found.target
    }

    @discardableResult
    public mutating func goForward(isAvailable: (DrawerNavigationTarget) -> Bool) -> DrawerNavigationTarget? {
        guard let found = forwardTarget(isAvailable: isAvailable) else { return nil }
        cursor = found.index
        return found.target
    }
}
