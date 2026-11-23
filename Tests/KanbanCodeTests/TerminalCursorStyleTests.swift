import Testing
import Foundation
import SwiftTerm

@Suite("Terminal cursor style")
struct TerminalCursorStyleTests {
    private final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    private func terminal() -> Terminal {
        Terminal(delegate: Delegate(), options: TerminalOptions(cols: 80, rows: 24))
    }

    /// Claude sends no DECSCUSR, and tmux resets the client's cursor with
    /// `CSI SP q` when a pane has no style, which a terminal reads as "the
    /// user's own cursor", not as a blinking block.
    @Test("A reset of the cursor style returns to the default style of the view")
    func resetUsesDefault() {
        let t = terminal()
        t.defaultCursorStyle = .steadyBar
        t.feed(text: "\u{1b}[2 q")
        #expect(t.options.cursorStyle == .steadyBlock)
        t.feed(text: "\u{1b}[ q")
        #expect(t.options.cursorStyle == .steadyBar)
        t.feed(text: "\u{1b}[4 q")
        t.feed(text: "\u{1b}[0 q")
        #expect(t.options.cursorStyle == .steadyBar)
    }

    @Test("An explicit style 1 is still a blinking block")
    func explicitBlinkBlock() {
        let t = terminal()
        t.defaultCursorStyle = .steadyBar
        t.feed(text: "\u{1b}[1 q")
        #expect(t.options.cursorStyle == .blinkBlock)
    }

    @Test("The default style is what the cursor shows before any program sets one")
    func defaultStyleApplies() {
        let t = terminal()
        t.defaultCursorStyle = .steadyBar
        #expect(t.options.cursorStyle == .steadyBar)
    }
}
