import Foundation

/// Decides, per press, whether the mouse goes to the program in a card's
/// terminal (Claude's fullscreen mode places its cursor on a click and copies
/// its own selection on release) or stays with the view, which selects text
/// itself. The drag and the release follow the press: a program that saw a
/// press and never its release waits for one, and a release without a press
/// is noise to it.
struct MouseForwardGate {
    /// Whether the press that is down went to the program.
    private(set) var dragForwarded = false

    /// `programOwnsMouse` is the pane's state (alternate screen and the mouse
    /// asked for); shift keeps the view's own selection, as iTerm does, and
    /// cmd keeps the press for opening a link.
    mutating func pressed(programOwnsMouse: Bool, shift: Bool, command: Bool) -> Bool {
        dragForwarded = programOwnsMouse && !shift && !command
        return dragForwarded
    }

    /// Whether the release goes to the program: only when its press did.
    mutating func released() -> Bool {
        defer { dragForwarded = false }
        return dragForwarded
    }
}
