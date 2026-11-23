import Testing
import Foundation
import AppKit
import SwiftTerm

@testable import KanbanCode

@Suite("Mouse forwarding to the program in a card")
struct MouseForwardGateTests {
    @Test("A press goes to a program that has the mouse")
    func pressForwarded() {
        var gate = MouseForwardGate()
        let r = gate.pressed(programOwnsMouse: true, shift: false, command: false); #expect(r)
        #expect(gate.dragForwarded)
    }

    @Test("A press stays with the view when the program did not ask for the mouse")
    func pressKeptWithoutProgramMouse() {
        var gate = MouseForwardGate()
        let r = !gate.pressed(programOwnsMouse: false, shift: false, command: false); #expect(r)
        #expect(!gate.dragForwarded)
    }

    /// iTerm keeps shift for the terminal's own selection, over a program
    /// that reports the mouse.
    @Test("Shift keeps the press for the view's own selection")
    func shiftKeepsPress() {
        var gate = MouseForwardGate()
        let r = !gate.pressed(programOwnsMouse: true, shift: true, command: false); #expect(r)
    }

    @Test("Cmd keeps the press for link opening")
    func commandKeepsPress() {
        var gate = MouseForwardGate()
        let r = !gate.pressed(programOwnsMouse: true, shift: false, command: true); #expect(r)
    }

    /// A press the program saw must get its release, and a press it did not
    /// see must not: the pane state can change between the two.
    @Test("The release follows the press, whatever the program wants by then")
    func releaseFollowsPress() {
        var gate = MouseForwardGate()
        _ = gate.pressed(programOwnsMouse: true, shift: false, command: false)
        let r = gate.released(); #expect(r)
        #expect(!gate.dragForwarded)

        _ = gate.pressed(programOwnsMouse: false, shift: false, command: false)
        let again = gate.released(); #expect(!again)
    }

    private func click(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: NSPoint(x: 85, y: 575), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private final class Recorder: TerminalViewDelegate {
        var sent: [UInt8] = []
        var text: String { String(decoding: sent, as: UTF8.self) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) { sent += data }
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    /// What Claude's fullscreen mode asks for: the alternate screen, mouse
    /// buttons and motion (1003) in SGR encoding (1006).
    @Test("A click is reported once as press and release, and the view keeps the mouse")
    @MainActor
    func clickReported() {
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let recorder = Recorder()
        view.terminalDelegate = recorder
        view.feed(text: "\u{1b}[?1049h\u{1b}[?1003h\u{1b}[?1006h")
        view.allowMouseReporting = false
        recorder.sent = []

        view.passMouseToProgram { view.mouseDown(with: click(.leftMouseDown)) }
        view.passMouseToProgram { view.mouseUp(with: click(.leftMouseUp)) }

        let reports = recorder.text.components(separatedBy: "\u{1b}[<").dropFirst()
        #expect(reports.count == 2)
        #expect(reports.first?.hasSuffix("M") == true)
        #expect(reports.last?.hasSuffix("m") == true)
        #expect(!view.allowMouseReporting)
    }
}
