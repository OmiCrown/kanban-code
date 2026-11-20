import Testing

@testable import KanbanCodeCore

@Suite("Who scrolls a card's terminal")
struct PaneScrollModeTests {
    @Test("a full-screen program that asked for the mouse gets the wheel")
    func fullScreenGetsWheel() {
        #expect(PaneScrollMode.parse("1 1\n") == .forwardToProgram)
    }

    @Test("a shell, or a program that did not ask for the mouse, is scrolled by tmux")
    func othersUseCopyMode() {
        #expect(PaneScrollMode.parse("0 0") == .tmuxCopyMode)
        #expect(PaneScrollMode.parse("0 1") == .tmuxCopyMode)
        #expect(PaneScrollMode.parse("1 0") == .tmuxCopyMode)
    }

    @Test("an answer that cannot be read means copy-mode, as before")
    func unreadableAnswer() {
        #expect(PaneScrollMode.parse("") == .tmuxCopyMode)
        #expect(PaneScrollMode.parse("can't find session: x") == .tmuxCopyMode)
    }
}
