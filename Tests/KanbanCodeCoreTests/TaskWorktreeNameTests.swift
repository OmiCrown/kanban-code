import Testing

@testable import KanbanCodeCore

@Suite("Worktree name of a new task")
struct TaskWorktreeNameTests {
    @Test("a name typed in the dialog goes to --worktree")
    func typedName() {
        #expect(TaskWorktree.flagName(create: true, supported: true, typed: "test") == "test")
        #expect(TaskWorktree.flagName(create: true, supported: true, typed: "  feature-x \n") == "feature-x")
    }

    @Test("an empty name asks for Claude's own random one")
    func emptyName() {
        #expect(TaskWorktree.flagName(create: true, supported: true, typed: nil) == "")
        #expect(TaskWorktree.flagName(create: true, supported: true, typed: "   ") == "")
    }

    @Test("no worktree when it is off or the assistant has none")
    func noWorktree() {
        #expect(TaskWorktree.flagName(create: false, supported: true, typed: "test") == nil)
        #expect(TaskWorktree.flagName(create: true, supported: false, typed: "test") == nil)
    }
}
