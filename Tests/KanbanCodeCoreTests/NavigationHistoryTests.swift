import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("NavigationHistory")
struct NavigationHistoryTests {
    private let any: (DrawerNavigationTarget) -> Bool = { _ in true }

    private func visited(_ ids: String...) -> NavigationHistory {
        var h = NavigationHistory()
        for id in ids { h.visit(.card(id)) }
        return h
    }

    @Test("Select A, B, A, B; back twice, forward twice keeps the order; forward at the end does nothing")
    func orderIsKept() {
        var h = visited("A", "B", "A", "B")
        #expect(h.goBack(isAvailable: any) == .card("A"))
        #expect(h.goBack(isAvailable: any) == .card("B"))
        #expect(h.goForward(isAvailable: any) == .card("A"))
        #expect(h.goForward(isAvailable: any) == .card("B"))
        #expect(h.goForward(isAvailable: any) == nil)
        #expect(h.cursor == 3)
    }

    @Test("The selection an arrow makes is not recorded again, so forward is not cleared")
    func arrowSelectionIsNotARecord() {
        var h = visited("A", "B", "C")
        let back = h.goBack(isAvailable: any)
        // The drawer now shows `back`; the view reports it as a visit.
        h.visit(back)
        #expect(h.entries.count == 3)
        #expect(h.forwardTarget(isAvailable: any)?.target == .card("C"))
    }

    @Test("A drawer that passes through closed on the way to the arrow's target keeps forward")
    func closedInBetweenKeepsForward() {
        var h = visited("A", "B", "C")
        let back = h.goBack(isAvailable: any)
        h.visit(nil)
        h.visit(back)
        #expect(h.forwardTarget(isAvailable: any)?.target == .card("C"))
        #expect(h.backTarget(isAvailable: any)?.target == .card("A"))
    }

    @Test("A new visit after going back drops what was ahead")
    func newVisitDropsForward() {
        var h = visited("A", "B", "C")
        h.goBack(isAvailable: any)
        h.visit(.card("D"))
        #expect(h.entries == [.card("A"), .card("B"), .card("D")])
        #expect(h.forwardTarget(isAvailable: any) == nil)
    }

    @Test("Opening the card already shown records nothing")
    func sameCardIsNotRecorded() {
        var h = visited("A")
        h.visit(.card("A"))
        h.visit(.card("A"))
        #expect(h.entries == [.card("A")])
    }

    @Test("Back skips entries that are not available and keeps them for later")
    func skipsUnavailable() {
        var h = visited("A", "B", "C")
        let notB: (DrawerNavigationTarget) -> Bool = { $0 != .card("B") }
        #expect(h.goBack(isAvailable: notB) == .card("A"))
        #expect(h.goForward(isAvailable: notB) == .card("C"))
        #expect(h.entries.contains(.card("B")))
        #expect(h.goBack(isAvailable: any) == .card("B"))
    }

    @Test("Entries of another project are skipped when the arrows are limited to one project")
    func staysInProject() {
        // t2 and test belong to project "app"; usage belongs to another.
        let project: [String: String] = ["t2": "app", "test": "app", "usage": "other"]
        let inApp: (DrawerNavigationTarget) -> Bool = {
            if case .card(let id) = $0 { return project[id] == "app" }
            return true
        }
        var h = visited("usage", "test", "t2")
        #expect(h.goBack(isAvailable: inApp) == .card("test"))
        #expect(h.goBack(isAvailable: inApp) == nil)
        #expect(h.goForward(isAvailable: inApp) == .card("t2"))
        #expect(h.goForward(isAvailable: inApp) == nil)
    }

    @Test("Nothing to go back to before the first visit, and at the first entry")
    func edges() {
        var h = NavigationHistory()
        #expect(h.goBack(isAvailable: any) == nil)
        #expect(h.goForward(isAvailable: any) == nil)
        h.visit(.card("A"))
        #expect(h.goBack(isAvailable: any) == nil)
    }

    @Test("The history keeps the last 100 entries")
    func limit() {
        var h = NavigationHistory()
        for i in 0..<130 { h.visit(.card("c\(i)")) }
        #expect(h.entries.count == NavigationHistory.limit)
        #expect(h.entries.first == .card("c30"))
        #expect(h.cursor == NavigationHistory.limit - 1)
    }
}
