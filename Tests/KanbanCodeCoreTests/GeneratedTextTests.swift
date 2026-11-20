import Testing
@testable import KanbanCodeCore

@Suite("GeneratedText")
struct GeneratedTextTests {
    @Test("A text the form made is not an edit, even after it made a newer one")
    func olderPreviewIsNotAnEdit() {
        var generated = GeneratedText()
        generated.record("claude --worktree t")
        generated.record("claude --worktree to")
        // The field change for the first text is reported after the second was made.
        #expect(!generated.isEdit("claude --worktree t"))
        #expect(!generated.isEdit("claude --worktree to"))
    }

    @Test("A text the user typed is an edit")
    func typedTextIsAnEdit() {
        var generated = GeneratedText()
        generated.record("claude --worktree")
        #expect(generated.isEdit("claude --worktree --model x"))
    }
}
