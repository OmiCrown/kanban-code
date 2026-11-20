import Foundation

/// The texts a form filled in by itself, to tell them from the user's edits.
///
/// A dialog that builds a command preview compared the field with the
/// preview of the moment to decide whether the user had edited it. A field
/// set to one preview and checked after a keystroke had made the next one
/// looked "edited", and from then on the form stopped following its own
/// options. A text the form made is remembered here whenever it is made, so
/// the check no longer depends on when it runs.
public struct GeneratedText: Equatable, Sendable {
    private var made: Set<String> = []

    public init() {}

    public mutating func record(_ text: String) {
        made.insert(text)
    }

    /// True when `text` is not one the form made, so the user typed it.
    public func isEdit(_ text: String) -> Bool {
        !made.contains(text)
    }
}
