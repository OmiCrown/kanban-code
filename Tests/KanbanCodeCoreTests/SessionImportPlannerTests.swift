import Foundation
import Testing

@testable import KanbanCodeCore

@Suite("What the Import sessions dialog offers")
struct SessionImportPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        _ id: String, project: String = "/work/app", profile: String = "/h/.claude-A",
        ageHours: Double = 1, prompt: String? = nil, name: String? = nil,
        entrypoint: String? = "cli", assistant: CodingAssistant = .claude
    ) -> Session {
        Session(
            id: id, name: name, firstPrompt: prompt ?? "prompt of \(id)", projectPath: project,
            messageCount: 4, modifiedTime: now.addingTimeInterval(-ageHours * 3600),
            jsonlPath: "\(profile)/projects/-work-app/\(id).jsonl",
            assistant: assistant, entrypoint: entrypoint)
    }

    private func running(_ id: String, name: String? = "named by Claude") -> RunningSession {
        RunningSession(
            pid: 100, sessionId: id, cwd: "/work/app", name: name,
            startedAt: now, procStart: nil, profilePath: "/h/.claude-A")
    }

    @Test("finished sessions are grouped by project and profile, newest first")
    func finishedGroupedByProjectAndProfile() {
        let offer = SessionImportPlanner.plan(
            sessions: [
                session("a-old", ageHours: 5),
                session("a-new", ageHours: 1),
                session("b", project: "/work/other", ageHours: 3),
                session("c", profile: "/h/.claude-B", ageHours: 9),
            ],
            running: [], excludedSessionIds: [])

        #expect(offer.finished.count == 3)
        #expect(offer.finished.map { $0.candidates.map(\.sessionId) }
                == [["a-new", "a-old"], ["b"], ["c"]])
        #expect(offer.finished[0].projectPath == "/work/app")
        #expect(offer.finished[0].profilePath == "/h/.claude-A")
        #expect(offer.finished[2].profilePath == "/h/.claude-B")
    }

    @Test("a session that runs and has a transcript is offered once, under Running")
    func runningListedOnceUnderRunning() {
        let offer = SessionImportPlanner.plan(
            sessions: [session("s1"), session("s2")],
            running: [running("s1")], excludedSessionIds: [])

        #expect(offer.running.map(\.sessionId) == ["s1"])
        #expect(offer.running.first?.title == "named by Claude")
        #expect(offer.running.first?.isRunning == true)
        #expect(offer.finished.flatMap(\.candidates).map(\.sessionId) == ["s2"])
    }

    @Test("a running instance without a transcript on disk is not offered")
    func runningWithoutTranscriptIsNotOffered() {
        let offer = SessionImportPlanner.plan(
            sessions: [session("s2")], running: [running("fresh")], excludedSessionIds: [])
        #expect(offer.running.isEmpty)
        #expect(offer.finished.flatMap(\.candidates).map(\.sessionId) == ["s2"])
    }

    @Test("excluded session ids are left out of both lists")
    func excludedAreLeftOut() {
        let offer = SessionImportPlanner.plan(
            sessions: [session("s1"), session("s2"), session("s3")],
            running: [running("s1")], excludedSessionIds: ["s1", "s2"])
        #expect(offer.running.isEmpty)
        #expect(offer.finished.flatMap(\.candidates).map(\.sessionId) == ["s3"])
    }

    @Test("headless runs and other assistants' sessions are left out")
    func headlessAndOtherAssistantsAreLeftOut() {
        let offer = SessionImportPlanner.plan(
            sessions: [
                session("keep"),
                session("headless", entrypoint: Session.headlessEntrypoint),
                session("codex", assistant: .codex),
            ],
            running: [], excludedSessionIds: [])
        #expect(offer.finished.flatMap(\.candidates).map(\.sessionId) == ["keep"])
    }

    @Test("the ten newest of each group are ticked, and every running one")
    func defaultSelectionTakesTenNewestPerGroup() {
        let many = (0..<15).map { session("f\($0)", ageHours: Double($0) + 2) }
        let other = [session("g0", project: "/work/other", ageHours: 40)]
        let offer = SessionImportPlanner.plan(
            sessions: many + other + [session("r1", ageHours: 100)],
            running: [running("r1")], excludedSessionIds: [])

        let expectedFinished = Set((0..<10).map { "f\($0)" })
        #expect(offer.defaultSelection == expectedFinished.union(["g0", "r1"]))
    }

    @Test("the card an import makes is manual, named, and not discovery-only")
    func makeLinkIsManualAndNamed() throws {
        let offer = SessionImportPlanner.plan(
            sessions: [session("s1", prompt: "fix the login")], running: [], excludedSessionIds: [])
        let candidate = try #require(offer.finished.first?.candidates.first)

        let link = SessionImportPlanner.makeLink(candidate, now: now)

        #expect(link.source == .manual)
        #expect(link.name == candidate.title)
        #expect(link.name?.isEmpty == false)
        #expect(link.projectPath == "/work/app")
        #expect(link.sessionLink?.sessionId == "s1")
        #expect(link.sessionLink?.sessionPath == "/h/.claude-A/projects/-work-app/s1.jsonl")
        #expect(link.column == .allSessions)
        #expect(!link.manualOverrides.column)
        #expect(!link.manuallyArchived)
        #expect(link.lastActivity == candidate.modifiedTime)
        #expect(!link.isDiscoveryOnly)
    }

    @Test("a session with no name and no prompt still gets a title")
    func emptyTitleFallsBack() throws {
        var bare = session("0123456789abcdef")
        bare.firstPrompt = nil
        let offer = SessionImportPlanner.plan(sessions: [bare], running: [], excludedSessionIds: [])
        let candidate = try #require(offer.finished.first?.candidates.first)
        #expect(candidate.title == "Session 01234567")
        #expect(SessionImportPlanner.makeLink(candidate, now: now).name == "Session 01234567")
    }
}
