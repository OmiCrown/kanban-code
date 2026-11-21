import Foundation
import Testing

@testable import KanbanCodeCore

/// A tmux that writes a transcript on `createSession` (as the user's shell
/// does for a real Claude), and records the command string that ran, so a
/// test can inspect which launcher binary and flags the pane got.
private final class CommandRecordingTmux: TmuxManagerPort, @unchecked Sendable {
    let transcriptFolder: String
    let resumeSessionId: String?
    var sessionId: String = UUID().uuidString.lowercased()
    var lastCommand: String?
    var lastSessionName: String?
    init(transcriptFolder: String, resumeSessionId: String? = nil) {
        self.transcriptFolder = transcriptFolder
        self.resumeSessionId = resumeSessionId
    }

    var transcriptPath: String { "\(transcriptFolder)/\(sessionId).jsonl" }

    func listSessions() async throws -> [TmuxSession] { [] }
    func createSession(name: String, path: String, command: String?) async throws {
        try FileManager.default.createDirectory(atPath: transcriptFolder, withIntermediateDirectories: true)
        lastCommand = command
        lastSessionName = name
        // Resume pane keeps the session id of the resumed card; launch pane
        // writes a fresh transcript so the engine's polling detects it.
        if resumeSessionId == nil {
            try "{\"type\":\"user\"}\n".write(toFile: transcriptPath, atomically: true, encoding: .utf8)
        }
    }
    func createSession(name: String, path: String, command: String?, environment: [String: String]) async throws {
        try await createSession(name: name, path: path, command: command)
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

@Suite("Master launch with a launch command", .serialized)
@MainActor
struct MasterLauncherTests {
    private struct Rig {
        let root: String
        let kanbanHome: String
        let defaultProjects: String
        let profile: ClaudeProfile
        let project: String
        let tmux: CommandRecordingTmux
        let store: BoardStore
        let engine: MasterEngine
    }

    /// A master whose Claude writes a new transcript into `profile`'s folder.
    /// `profileLauncherId` sets the profile's default launcher (nil = plain).
    /// `launchers` seeds `Settings.claudeLaunchers`.
    private func makeRig(
        profileLauncherId: String? = "codemie",
        launchers: [ClaudeLauncher] = [.codemie],
        resumeSessionId: String? = nil
    ) throws -> Rig {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("master-launcher-\(UUID().uuidString)")
        let fm = FileManager.default
        let kanbanHome = root + "/kanban-home"
        let defaultProjects = root + "/dot-claude/projects"
        // The profile's project roots contain `project`, so it owns the card.
        let profile = ClaudeProfile(
            path: root + "/.claude-Client",
            enabled: true,
            projectRoots: [root + "/work"],
            launcherId: profileLauncherId,
            home: root)
        let project = root + "/work/app"
        try fm.createDirectory(atPath: kanbanHome, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: defaultProjects, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: profile.projectsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: project, withIntermediateDirectories: true)

        var settings = Settings()
        settings.claudeProfiles = [profile]
        settings.claudeLaunchers = launchers
        settings.launchersSeeded = true
        try JSONEncoder().encode(settings).write(to: URL(fileURLWithPath: kanbanHome + "/settings.json"))

        let encoded = SessionFileMover.encodeProjectPath(project)
        let folder = profile.projectsDirectory + "/" + encoded
        let tmux = CommandRecordingTmux(transcriptFolder: folder, resumeSessionId: resumeSessionId)
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

    /// Dispatches `.createManualTask` for a fresh card and launches it with
    /// `launcherCommand`, returning the updated link.
    private func launchNewCard(
        _ rig: Rig,
        cardId: String = "card_launcher",
        launcherCommand: String? = nil,
        runRemotely: Bool = false
    ) async -> Link? {
        rig.store.dispatch(.createManualTask(Link(
            id: cardId, name: "Launcher card", projectPath: rig.project, column: .backlog)))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            rig.engine.launch(
                cardId: cardId, prompt: "", projectPath: rig.project, worktreeName: nil,
                runRemotely: runRemotely, launcherCommand: launcherCommand
            ) { _ in done.resume() }
        }
        return rig.store.state.links[cardId]
    }

    // MARK: - Launch

    @Test("an explicit chosen command is used and stored on the card")
    func explicitChoiceIsUsedAndStored() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let link = await launchNewCard(rig, launcherCommand: "codemie-claude")
        #expect(rig.tmux.lastCommand?.contains(" codemie-claude ") == true)
        #expect(link?.launcherCommand == "codemie-claude")
    }

    @Test("an explicit plain overrides a profile default and stores nothing")
    func explicitPlainOverridesProfileDefault() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let link = await launchNewCard(rig, launcherCommand: "claude")
        #expect(rig.tmux.lastCommand?.contains(" claude ") == true)
        #expect(rig.tmux.lastCommand?.contains("codemie-claude") == false)
        #expect(link?.launcherCommand == nil)
    }

    @Test("no explicit choice takes the profile default and is stored")
    func noChoiceTakesProfileDefault() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let link = await launchNewCard(rig, launcherCommand: nil)
        #expect(rig.tmux.lastCommand?.contains(" codemie-claude ") == true)
        #expect(link?.launcherCommand == "codemie-claude")
    }

    @Test("a remote (mutagen) launch stores nothing and runs plain claude")
    func remoteStoresNothing() async throws {
        // The engine is supposed to skip the resolve/store step when
        // `isRemote` is true. A mutagen-configured launch, with the project
        // under `remote.localPath`, takes the engine's remote branch so the
        // guard is actually exercised in a running engine. The mutagen CLI
        // is expected to be absent in the test environment; its calls are
        // caught by the engine's `try?`, and `RemoteShellManager.deploy()`
        // only writes an idempotent wrapper under `~/.kanban-code/remote/`.
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        // Settings has a mutagen remote whose localPath contains the project.
        var settings = Settings()
        settings.claudeProfiles = [rig.profile]
        settings.claudeLaunchers = [.codemie]
        settings.launchersSeeded = true
        settings.remoteMode = .mutagen
        settings.remote = RemoteSettings(
            host: "invalid.example", remotePath: "/tmp/remote", localPath: rig.root + "/work")
        try JSONEncoder().encode(settings).write(to: URL(fileURLWithPath: rig.kanbanHome + "/settings.json"))
        rig.store.dispatch(.createManualTask(Link(
            id: "card_remote", name: "Remote", projectPath: rig.project, column: .backlog)))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            rig.engine.launch(
                cardId: "card_remote", prompt: "", projectPath: rig.project, worktreeName: nil,
                runRemotely: true
            ) { _ in done.resume() }
        }
        #expect(rig.store.state.links["card_remote"]?.launcherCommand == nil)
        #expect(rig.tmux.lastCommand?.contains("codemie-claude") == false)
    }

    // MARK: - Resume

    @Test("a card's stored launcher command is what resume runs")
    func resumeUsesStoredCommand() async throws {
        let sessionId = UUID().uuidString.lowercased()
        let rig = try makeRig(resumeSessionId: sessionId)
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let encoded = SessionFileMover.encodeProjectPath(rig.project)
        let sessionPath = rig.profile.projectsDirectory + "/" + encoded + "/" + sessionId + ".jsonl"
        try FileManager.default.createDirectory(
            atPath: (sessionPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "{\"type\":\"user\"}\n".write(toFile: sessionPath, atomically: true, encoding: .utf8)
        rig.store.dispatch(.createManualTask(Link(
            id: "card_resume", name: "Resume card", projectPath: rig.project, column: .inProgress,
            launcherCommand: "codemie-claude",
            sessionLink: SessionLink(sessionId: sessionId, sessionPath: sessionPath))))
        _ = rig.engine.resume(cardId: "card_resume", runRemotely: false, commandOverride: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.tmux.lastCommand?.contains(" codemie-claude ") == true)
        #expect(rig.tmux.lastCommand?.contains("--resume \(sessionId)") == true)
    }

    @Test("an imported session (no stored command) resumes with plain claude")
    func importedSessionResumesPlain() async throws {
        let sessionId = UUID().uuidString.lowercased()
        let rig = try makeRig(resumeSessionId: sessionId)
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let encoded = SessionFileMover.encodeProjectPath(rig.project)
        let sessionPath = rig.profile.projectsDirectory + "/" + encoded + "/" + sessionId + ".jsonl"
        try FileManager.default.createDirectory(
            atPath: (sessionPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "{\"type\":\"user\"}\n".write(toFile: sessionPath, atomically: true, encoding: .utf8)
        // Imported: a session with no launcherCommand, in a CodeMie-default project.
        rig.store.dispatch(.createManualTask(Link(
            id: "card_imported", name: "Imported", projectPath: rig.project, column: .inProgress,
            launcherCommand: nil,
            sessionLink: SessionLink(sessionId: sessionId, sessionPath: sessionPath))))
        _ = rig.engine.resume(cardId: "card_imported", runRemotely: false, commandOverride: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.tmux.lastCommand?.contains(" claude ") == true)
        #expect(rig.tmux.lastCommand?.contains("--resume \(sessionId)") == true)
        #expect(rig.tmux.lastCommand?.contains("codemie-claude") == false)
    }

    @Test("settings edits after a card started do not change its resume command")
    func editedSettingsDoNotChangeStartedCard() async throws {
        let sessionId = UUID().uuidString.lowercased()
        // The settings now have an empty launchers list, but the card was
        // started earlier with codemie-claude and kept the command on its link.
        let rig = try makeRig(profileLauncherId: nil, launchers: [], resumeSessionId: sessionId)
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        let encoded = SessionFileMover.encodeProjectPath(rig.project)
        let sessionPath = rig.profile.projectsDirectory + "/" + encoded + "/" + sessionId + ".jsonl"
        try FileManager.default.createDirectory(
            atPath: (sessionPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "{\"type\":\"user\"}\n".write(toFile: sessionPath, atomically: true, encoding: .utf8)
        rig.store.dispatch(.createManualTask(Link(
            id: "card_kept", name: "Kept", projectPath: rig.project, column: .inProgress,
            launcherCommand: "codemie-claude",
            sessionLink: SessionLink(sessionId: sessionId, sessionPath: sessionPath))))
        _ = rig.engine.resume(cardId: "card_kept", runRemotely: false, commandOverride: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.tmux.lastCommand?.contains(" codemie-claude ") == true)
        #expect(rig.tmux.lastCommand?.contains("--resume \(sessionId)") == true)
    }
}
