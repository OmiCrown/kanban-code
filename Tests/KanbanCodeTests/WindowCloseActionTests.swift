import AppKit
import Testing

@testable import KanbanCode

@Suite("Closing the main window")
struct WindowCloseActionTests {
    @Test("the red button puts the window away")
    func redButtonHides() {
        #expect(WindowCloseAction.forEvent(.leftMouseUp) == .hideWindow)
        #expect(WindowCloseAction.forEvent(.leftMouseDown) == .hideWindow)
    }

    @Test("Cmd+W and anything else closes the terminal tab")
    func keyboardClosesTab() {
        #expect(WindowCloseAction.forEvent(.keyDown) == .closeTerminalTab)
        #expect(WindowCloseAction.forEvent(nil) == .closeTerminalTab)
    }
}
