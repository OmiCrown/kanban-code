import Foundation
import KanbanCodeCore
import Testing

@testable import KanbanCode

@Suite("Card action catalog")
@MainActor
struct CardActionCatalogTests {

    /// Records every action that runs, by the name of its property on
    /// `CardActionsMenuActions`.
    final class Recorder {
        var hits: Set<String> = []
        var copied: [String] = []
        var unarchived: [String] = []
        var markedDone: [String] = []
    }

    private static func actions(_ r: Recorder, archive: Bool = true) -> CardActionsMenuActions {
        CardActionsMenuActions(
            onStart: { r.hits.insert("onStart") },
            onResume: { r.hits.insert("onResume") },
            onFork: { _ in r.hits.insert("onFork") },
            onRenameRequest: { r.hits.insert("onRenameRequest") },
            onSetPinned: { _ in r.hits.insert("onSetPinned") },
            onSetSelfCompactContextThreshold: { _ in r.hits.insert("onSetSelfCompactContextThreshold") },
            onCopyResumeCmd: { r.hits.insert("onCopyResumeCmd") },
            onCopyConversationMarkdown: { r.hits.insert("onCopyConversationMarkdown") },
            subagentCount: 2,
            onShowSubagents: { r.hits.insert("onShowSubagents") },
            onTrimSession: { r.hits.insert("onTrimSession") },
            onCheckpoint: { r.hits.insert("onCheckpoint") },
            onAddLink: { r.hits.insert("onAddLink") },
            onUnlink: { _ in r.hits.insert("onUnlink") },
            onDiscover: { r.hits.insert("onDiscover") },
            onCleanupWorktree: { r.hits.insert("onCleanupWorktree") },
            canCleanupWorktree: true,
            onArchive: archive ? { r.hits.insert("onArchive") } : nil,
            onDelete: { r.hits.insert("onDelete") },
            onMoveToProject: { _ in r.hits.insert("onMoveToProject") },
            onMoveToFolder: { r.hits.insert("onMoveToFolder") },
            onMigrateAssistant: { _ in r.hits.insert("onMigrateAssistant") },
            onShowPromptHistory: { r.hits.insert("onShowPromptHistory") },
            onShowVault: { r.hits.insert("onShowVault") }
        )
    }

    private static func environment(_ r: Recorder) -> CardActionEnvironment {
        CardActionEnvironment(
            copy: { r.copied.append($0) },
            open: { _ in },
            moveCard: { _, _ in },
            pauseMachine: { _ in },
            destroyMachine: { _ in },
            unarchive: { r.unarchived.append($0) },
            markDone: { r.markedDone.append($0) },
            requestAddLink: { _ in },
            continueTargets: [("box", "box")],
            isSharedMachine: { _ in false }
        )
    }

    private static func card(
        _ id: String,
        column: KanbanCodeColumn = .inProgress,
        archived: Bool = false
    ) -> KanbanCodeCard {
        KanbanCodeCard(link: Link(
            id: id,
            projectPath: "/repo",
            column: column,
            manuallyArchived: archived,
            source: .manual,
            sessionLink: SessionLink(sessionId: "sess-\(id)", sessionPath: "/tmp/\(id).jsonl"),
            tmuxLink: TmuxLink(sessionName: "tmux-\(id)"),
            worktreeLink: WorktreeLink(path: "/repo/.worktrees/\(id)", branch: "feat/\(id)"),
            prLinks: [PRLink(number: 7, url: "https://github.com/acme/repo/pull/7")],
            issueLink: IssueLink(number: 3, url: "https://github.com/acme/repo/issues/3")
        ))
    }

    private static func catalog(
        _ card: KanbanCodeCard,
        _ r: Recorder,
        archive: Bool = true,
        offersMarkDone: Bool = false
    ) -> CardActionCatalog {
        CardActionCatalog(
            card: card,
            actions: actions(r, archive: archive),
            showBranchInfo: true,
            availableProjects: [(name: "Other", path: "/other")],
            enabledAssistants: CodingAssistant.allCases,
            offersMarkDone: offersMarkDone,
            environment: environment(r)
        )
    }

    private static func markDoneItem(_ catalog: CardActionCatalog) -> CardActionItem? {
        catalog.sections.joined().first { $0.id == "markDone" }
    }

    @Test("Mark as Done is offered when the project merges without a PR")
    func markDoneOfferedWithFlag() throws {
        let catalog = Self.catalog(Self.card("a", column: .waiting), Recorder(), offersMarkDone: true)
        let item = try #require(Self.markDoneItem(catalog))
        #expect(item.title == "Mark as Done")
        #expect(catalog.paletteEntries.contains { $0.title == "Mark Card as Done" })
    }

    @Test("Mark as Done is not offered without the flag")
    func markDoneHiddenWithoutFlag() {
        let catalog = Self.catalog(Self.card("a", column: .waiting), Recorder())
        #expect(Self.markDoneItem(catalog) == nil)
    }

    @Test("Mark as Done is not offered for a card already in Done or archived")
    func markDoneHiddenInDoneAndArchived() {
        let done = Self.catalog(Self.card("d", column: .done), Recorder(), offersMarkDone: true)
        let archived = Self.catalog(Self.card("x", column: .allSessions, archived: true), Recorder(), offersMarkDone: true)
        #expect(Self.markDoneItem(done) == nil)
        #expect(Self.markDoneItem(archived) == nil)
    }

    @Test("Mark as Done is not offered for a card on a boxd machine")
    func markDoneHiddenOnBoxdMachine() {
        var link = Self.card("b", column: .waiting).link
        link.remote = RemoteLink(mode: .boxd, machineName: "kanban-box")
        let catalog = Self.catalog(KanbanCodeCard(link: link), Recorder(), offersMarkDone: true)
        #expect(Self.markDoneItem(catalog) == nil)
    }

    @Test("Mark as Done asks the environment to close this card")
    func markDoneRunsEnvironment() throws {
        let r = Recorder()
        let catalog = Self.catalog(Self.card("run", column: .waiting), r, offersMarkDone: true)
        let item = try #require(Self.markDoneItem(catalog))
        guard case .perform(let run) = item.kind else { Issue.record("not a plain action"); return }
        run()
        #expect(r.markedDone == ["run"])
    }

    @Test("the palette reaches every action of CardActionsMenuActions")
    func paletteCoversEveryMenuAction() {
        let r = Recorder()
        let catalogs = [
            Self.catalog(Self.card("live"), r),
            Self.catalog(KanbanCodeCard(link: Link(id: "fresh", projectPath: "/repo", column: .backlog, source: .manual)), r),
            Self.catalog(Self.card("archived", archived: true), r),
        ]
        for catalog in catalogs {
            for entry in catalog.paletteEntries { entry.run() }
        }

        let closureNames = Mirror(reflecting: Self.actions(Recorder())).children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            return String(describing: type(of: child.value)).contains("->") ? label : nil
        }
        #expect(!closureNames.isEmpty)
        for name in closureNames {
            #expect(r.hits.contains(name), "no palette entry runs \(name)")
        }
    }

    @Test("every enabled menu item is a palette entry")
    func paletteMatchesMenu() {
        let catalog = Self.catalog(Self.card("live"), Recorder())
        var menuIds: [String] = []
        for item in catalog.sections.joined() where !item.isDisabled {
            switch item.kind {
            case .perform: menuIds.append("card-action:\(item.id)")
            case .submenu(let children):
                menuIds += children.filter { !$0.isDisabled }.map { "card-action:\($0.id)" }
            }
        }
        #expect(catalog.paletteEntries.map(\.id) == menuIds)
        #expect(Set(menuIds).count == menuIds.count, "palette ids must be unique")
    }

    @Test("Copy Card ID is offered and copies the card id")
    func copyCardId() throws {
        let r = Recorder()
        let catalog = Self.catalog(Self.card("abc"), r)
        let entry = try #require(catalog.paletteEntries.first { $0.title == "Copy Card ID" })
        entry.run()
        #expect(r.copied == ["abc"])
    }

    @Test("an archived card offers Unarchive and Delete, a live one Archive")
    func archiveEntries() throws {
        let r = Recorder()
        let archived = Self.catalog(Self.card("old", archived: true), r).paletteEntries.map(\.title)
        #expect(archived.contains("Unarchive Card"))
        #expect(archived.contains("Delete Card"))
        #expect(!archived.contains("Archive Card"))

        let live = Self.catalog(Self.card("new"), r).paletteEntries
        #expect(live.contains { $0.title == "Archive Card" && $0.shortcut == .archiveCard })
        #expect(!live.contains { $0.title == "Delete Card" })

        try #require(Self.catalog(Self.card("old", archived: true), r).paletteEntries
            .first { $0.title == "Unarchive Card" }).run()
        #expect(r.unarchived == ["old"])
    }

    @Test("submenu entries carry their submenu's name")
    func submenuTitles() {
        let titles = Self.catalog(Self.card("live"), Recorder()).paletteEntries.map(\.title)
        #expect(titles.contains("Continue on: box"))
        #expect(titles.contains("Move to Project: Other"))
        #expect(titles.contains("Move to Project: Select Folder..."))
        #expect(titles.contains("Self-Compact Threshold: Use Global Settings (current)"))
        #expect(titles.contains("PR #7: Copy PR Link"))
        #expect(titles.contains("Branch feat/live: Unlink Branch"))
    }
}
