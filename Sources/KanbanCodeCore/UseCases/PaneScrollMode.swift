import Foundation

/// Who answers the mouse wheel over a card's terminal.
public enum PaneScrollMode: Equatable, Sendable {
    /// A shell or a scrolling program: tmux copy-mode walks tmux's history.
    case tmuxCopyMode
    /// A full-screen program (Claude's `tui: fullscreen`) on the alternate
    /// screen that asked for the mouse. It keeps its own scrollback and tmux
    /// has none to show, so the wheel goes to the program.
    case forwardToProgram

    /// The `-F` format whose answer `parse` reads.
    public static let tmuxFormat = "#{alternate_on} #{mouse_any_flag}"

    public static func parse(_ output: String) -> PaneScrollMode {
        let flags = output.split(whereSeparator: \.isWhitespace).map(String.init)
        return flags == ["1", "1"] ? .forwardToProgram : .tmuxCopyMode
    }
}
