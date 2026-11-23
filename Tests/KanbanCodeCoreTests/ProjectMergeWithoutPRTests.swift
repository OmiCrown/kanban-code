import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("Project: merge without PR")
struct ProjectMergeWithoutPRTests {

    @Test("A project written before the flag existed decodes as off")
    func projectDecodesWithoutKey() throws {
        let json = #"{"path":"/p","name":"p","visible":true}"#
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.mergeWithoutPR == nil)
    }

    @Test("The flag survives an encode and decode")
    func projectRoundTripsFlag() throws {
        let data = try JSONEncoder().encode(Project(path: "/p", mergeWithoutPR: true))
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded.mergeWithoutPR == true)
    }

    @Test("A card takes the flag of its project by project path, worktree or not")
    func stateReportsFlagByProjectPath() {
        var state = AppState()
        state.configuredProjects = [
            Project(path: "/p", mergeWithoutPR: true),
            Project(path: "/q"),
        ]

        let plain = Link(id: "card_plain", projectPath: "/p")
        var inWorktree = Link(id: "card_wt", projectPath: "/p")
        inWorktree.worktreeLink = WorktreeLink(path: "/p/.claude/worktrees/x", branch: "x")

        #expect(state.mergesWithoutPR(plain))
        #expect(state.mergesWithoutPR(inWorktree))
        #expect(!state.mergesWithoutPR(Link(id: "card_q", projectPath: "/q")))
        #expect(!state.mergesWithoutPR(Link(id: "card_other", projectPath: "/other")))
        #expect(!state.mergesWithoutPR(Link(id: "card_none", projectPath: nil)))
    }
}
