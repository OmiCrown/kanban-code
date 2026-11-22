import Testing
import Foundation
import AppKit
import SwiftTerm

@testable import KanbanCode

/// tmux sends the difference between two screens, not the whole screen. A view
/// that throws away part of that stream is left with rows from different moments:
/// lines of the transcript on the row of the input field. Scrolling a full-screen
/// program makes it repaint on every tick, so the backlog is what gets dropped.
@Suite("Terminal output while the wheel scrolls a program")
@MainActor
struct TerminalWheelBacklogTests {
    private nonisolated static let rows = 40
    private nonisolated static let cols = 120

    /// The first half paints every row, the second half only the last five,
    /// as tmux does when only the bottom of the screen changes.
    private nonisolated static let stream: [UInt8] = {
        func frame(row: Int, number: Int) -> String {
            let text = "row \(row) frame \(number) "
            let padded = text + String(repeating: ".", count: cols - 1 - text.count)
            return "\u{1b}[\(row + 1);1H\(padded)"
        }
        var out = ""
        for number in 0..<300 { out += frame(row: number % rows, number: number) }
        for number in 300..<600 { out += frame(row: rows - 5 + number % 5, number: number) }
        return Array(out.utf8)
    }()

    private func wheel() -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)!
        return NSEvent(cgEvent: event)!
    }

    private func makeView() -> BatchedTerminalView {
        let view = BatchedTerminalView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.terminal.resize(cols: Self.cols, rows: Self.rows)
        return view
    }

    private func screen(of view: BatchedTerminalView) -> [String] {
        (0..<Self.rows).map { view.terminal.getLine(row: $0)?.translateToString(trimRight: true) ?? "" }
    }

    /// The screen after the whole stream, nothing dropped.
    private func exactScreen() async throws -> [String] {
        let view = makeView()
        view.lossless = true
        view.dataReceived(slice: Self.stream[...])
        try await Task.sleep(for: .milliseconds(300))
        return screen(of: view)
    }

    @Test("The stream is one the view cannot drop without changing the screen")
    func streamIsSensitive() async throws {
        #expect(Self.stream.count > 64 * 1024)
        let view = makeView()
        view.dataReceived(slice: Self.stream[...])
        try await Task.sleep(for: .milliseconds(300))
        #expect(screen(of: view) != (try await exactScreen()))
    }

    @Test("Output that arrives while the wheel is passed to a program is not dropped")
    func nothingDroppedWhileScrolling() async throws {
        let view = makeView()
        view.passWheelToProgram(wheel())
        view.dataReceived(slice: Self.stream[...])
        try await Task.sleep(for: .milliseconds(500))
        #expect(screen(of: view) == (try await exactScreen()))
    }
}
