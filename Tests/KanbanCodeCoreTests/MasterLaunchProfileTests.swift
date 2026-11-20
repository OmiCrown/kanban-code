import Foundation
import Testing

@testable import KanbanCodeCore

/// A tmux that, on `createSession`, writes the transcript a real Claude would
/// write: into `transcriptFolder`, which is where the user's shell sent it.
private final class TranscriptWritingTmux: TmuxManagerPort, @unchecked Sendable {
    let transcriptFolder: String
    let sessionId = UUID().uuidString.lowercased()
    init(transcriptFolder: String) { self.transcriptFolder = transcriptFolder }

    var transcriptPath: String { "\(transcriptFolder)/\(sessionId).jsonl" }

    func listSessions() async throws -> [TmuxSession] { [] }
    func createSession(name: String, path: String, command: String?) async throws {
        try FileManager.default.createDirectory(atPath: transcriptFolder, withIntermediateDirectories: true)
        try "{\"type\":\"user\"}\n".write(toFile: transcriptPath, atomically: true, encoding: .utf8)
    }
    func killSession(name: String) async throws {}
    func findSessionForWorktree(sessions: [TmuxSession], worktreePath: String, branch: String?) -> TmuxSession? { nil }
    func sendPrompt(to sessionName: String, text: String) async throws {}
    func pastePrompt(to sessionName: String, text: String) async throws {}
    func pasteText(to sessionName: String, text: String) async throws {}
    func submitPrompt(to sessionName: String) async throws {}
    func capturePane(sessionName: String) async throws -> String { "" }
    func sendBracketedPaste(to sessionName: String) async throws {}
    func isAvailable() async -> Bool { true }
}

@Suite("Master launch with Claude profiles", .serialized)
@MainActor
struct MasterLaunchProfileTests {
    private struct Rig {
        let root: String
        let kanbanHome: String
        let defaultProjects: String
        let profile: ClaudeProfile
        let project: String
        let tmux: TranscriptWritingTmux
        let store: BoardStore
        let engine: MasterEngine
    }

    /// A master whose Claude sends its transcript into `profile`'s folder,
    /// as the user's shell does for a project under that profile's path.
    private func makeRig(profileEnabled: Bool, transcriptsGoToProfile: Bool = true) throws -> Rig {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("master-launch-profile-\(UUID().uuidString)")
        let fm = FileManager.default
        let kanbanHome = root + "/kanban-home"
        let defaultProjects = root + "/dot-claude/projects"
        let profile = ClaudeProfile(
            path: root + "/.claude-Client", enabled: profileEnabled, home: root)
        let project = root + "/work/Client/app"
        try fm.createDirectory(atPath: kanbanHome, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: defaultProjects, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: profile.projectsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: project, withIntermediateDirectories: true)

        var settings = Settings()
        settings.claudeProfiles = [profile]
        try JSONEncoder().encode(settings).write(to: URL(fileURLWithPath: kanbanHome + "/settings.json"))

        let encoded = SessionFileMover.encodeProjectPath(project)
        let folder = (transcriptsGoToProfile ? profile.projectsDirectory : defaultProjects) + "/" + encoded
        let tmux = TranscriptWritingTmux(transcriptFolder: folder)
        let coordination = CoordinationStore(basePath: kanbanHome)
        let store = BoardStore(
            effectHandler: EffectHandler(
                coordinationStore: coordination, tmuxAdapter: tmux,
                queuedPromptJournal: QueuedPromptJournal(basePath: kanbanHome)),
            discovery: ClaudeCodeSessionDiscovery(),
            coordinationStore: coordination
        )
        var platform = MasterPlatform()
        platform.kanbanHome = kanbanHome
        platform.projectsDirectory = root + "/Projects"
        platform.claudeProjectsDirectory = defaultProjects
        let engine = MasterEngine(
            store: store,
            settingsStore: SettingsStore(basePath: kanbanHome),
            launcher: LaunchSession(tmux: tmux),
            tmux: RoutingTmuxAdapter(rush: RushCliAdapter(executable: "/nonexistent/rush")),
            registry: CodingAssistantRegistry(),
            platform: platform
        )
        store.dispatch(.localMachineLoaded(MachineIdentity(name: "test")))
        return Rig(
            root: root, kanbanHome: kanbanHome, defaultProjects: defaultProjects,
            profile: profile, project: project, tmux: tmux, store: store, engine: engine)
    }

    /// Launches a card with no prompt (nothing to wait for) and returns its session link.
    private func launchCard(_ rig: Rig) async -> SessionLink? {
        rig.store.dispatch(.createManualTask(Link(
            id: "card_profile", name: "Profile card", projectPath: rig.project, column: .backlog)))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            rig.engine.launch(
                cardId: "card_profile", prompt: "", projectPath: rig.project, worktreeName: nil,
                runRemotely: false, commandOverride: "claude"
            ) { _ in done.resume() }
        }
        return rig.store.state.links["card_profile"]?.sessionLink
    }

    @Test("roots: the default folder and the enabled profiles that exist, no disabled ones, no duplicates")
    func roots() throws {
        let rig = try makeRig(profileEnabled: true)
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let roots = rig.engine.claudeProjectsRoots()
        #expect(roots.first == rig.defaultProjects)
        #expect(roots.contains(rig.profile.projectsDirectory))
        #expect(Set(roots).count == roots.count)

        let off = try makeRig(profileEnabled: false)
        defer { try? FileManager.default.removeItem(atPath: off.root) }
        #expect(!off.engine.claudeProjectsRoots().contains(off.profile.projectsDirectory))
    }

    @Test("directories: each root gets the project folder, worktree folders only on request")
    func directories() throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("session-dirs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let a = root + "/a", b = root + "/b"
        for dir in [a + "/-w-app", a + "/-w-app-.claude-worktrees-x", a + "/-w-other", b + "/-w-app-.claude-worktrees-y"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        #expect(MasterEngine.sessionDirectories(projectsRoots: [a, b], encodedProject: "-w-app", includeWorktrees: false)
                == [a + "/-w-app", b + "/-w-app"])
        #expect(MasterEngine.sessionDirectories(projectsRoots: [a, b], encodedProject: "-w-app", includeWorktrees: true)
                == [a + "/-w-app", a + "/-w-app-.claude-worktrees-x", b + "/-w-app", b + "/-w-app-.claude-worktrees-y"])
    }

    @Test("a new session that Claude writes into a profile folder is linked to its card")
    func launchFindsTranscriptInProfile() async throws {
        let rig = try makeRig(profileEnabled: true)
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let link = await launchCard(rig)
        #expect(link?.sessionId == rig.tmux.sessionId)
        #expect(link?.sessionPath == rig.tmux.transcriptPath)
        #expect(ClaudeProfile.configDirectory(ofTranscript: link?.sessionPath ?? "") == rig.profile.path)
    }

    @Test("a transcript in the default folder is still found when a profile is enabled")
    func launchFindsTranscriptInDefault() async throws {
        let rig = try makeRig(profileEnabled: true, transcriptsGoToProfile: false)
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let link = await launchCard(rig)
        #expect(link?.sessionPath == rig.tmux.transcriptPath)
    }

    @Test("a disabled profile is not scanned: its transcript is not linked")
    func launchIgnoresDisabledProfile() async throws {
        let rig = try makeRig(profileEnabled: false)
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let link = await launchCard(rig)
        #expect(link?.sessionPath == nil)
    }
}
