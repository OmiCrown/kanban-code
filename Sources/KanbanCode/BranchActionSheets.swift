import SwiftUI
import KanbanCodeCore
import struct KanbanCodeCore.Link

// MARK: - Text

/// The text of the Merge into main sheet, kept apart from the view so it can be tested.
enum MergeSheetText {
    /// Longest list of commits or paths shown; the rest is summed up as "and N more".
    static let listCap = 20

    /// Cuts `items` to `listCap` and says how many were left out.
    static func capped(_ items: [String]) -> [String] {
        guard items.count > listCap else { return items }
        return Array(items.prefix(listCap)) + ["and \(items.count - listCap) more"]
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// Indented, so the sheet can tell a list entry from a heading.
    private static func commitLines(_ commits: [CommitLine]) -> [String] {
        capped(commits.map { "  \($0.sha.prefix(7)) \($0.subject)" })
    }

    private static func pathLines(_ paths: [String]) -> [String] {
        capped(paths.map { "  \($0)" })
    }

    /// What the sheet says about the state of the branch. Commits are listed oldest
    /// first on purpose: that is the order `fastForward(commits:)` carries and the
    /// order they enter main.
    static func lines(for p: MergePreflight) -> [String] {
        let main = p.mainBranch ?? "main"
        var out: [String] = []

        switch p.relation {
        case .fastForward(let commits):
            out.append("\(count(commits.count, "commit")) \(commits.count == 1 ? "goes" : "go") into \(main)")
            out += commitLines(commits)
        case .upToDate:
            out.append("\(p.branch) is already in \(main)")
        case .diverged(let ahead, let behind):
            out.append("\(p.branch) and \(main) have diverged")
            out.append("\(count(ahead.count, "commit")) only on \(p.branch):")
            out += commitLines(ahead)
            out.append("\(count(behind.count, "commit")) only in \(main):")
            out += commitLines(behind)
        case .mainNotOnMain(let current):
            out.append("The main checkout is on \(current.map { "'\($0)'" } ?? "a detached HEAD"), not main or master.")
        }

        if !p.mainDirtyPaths.isEmpty {
            out.append("Warning: the main checkout has \(count(p.mainDirtyPaths.count, "uncommitted path")):")
            out += pathLines(p.mainDirtyPaths)
        }
        if !p.worktreeDirtyPaths.isEmpty {
            out.append("\(count(p.worktreeDirtyPaths.count, "uncommitted path")) in the worktree will not go with the merge:")
            out += pathLines(p.worktreeDirtyPaths)
        }

        let different = p.docs.filter { $0.state == .different }.map { "\($0.path) differs in \(main); resolve it before merging." }
        out += capped(different)
        return out
    }

    /// The banner shown when the sheet closes, or the text kept on the sheet for a refusal.
    static func resultNotice(_ o: MergeOutcome) -> String {
        switch o {
        case .merged(let oldHead, let newHead, let copied, let skipped):
            return ([
                "Merged into the main checkout: \(oldHead.prefix(7))..\(newHead.prefix(7))"
            ] + docSummary(copied: copied, skipped: skipped)).joined(separator: "; ")
        case .alreadyInMain(let copied, let skipped):
            return (["The branch is already in main; nothing to merge"] + docSummary(copied: copied, skipped: skipped))
                .joined(separator: "; ")
        case .refused(let text):
            return text
        }
    }

    /// `skipped` holds files identical in main and files that could not be copied
    /// after the merge, so it is worded for both.
    private static func docSummary(copied: [String], skipped: [String]) -> [String] {
        var parts: [String] = []
        if !copied.isEmpty { parts.append("\(count(copied.count, "file")) copied") }
        if !skipped.isEmpty {
            parts.append("\(count(skipped.count, "file")) not copied: already identical in main, or could not be copied; see the log")
        }
        return parts
    }
}

// MARK: - Receiver

/// The card a branch action works on, captured when the menu item is chosen.
struct BranchActionTarget: Identifiable, Equatable {
    let cardId: String
    let worktreePath: String
    let branch: String
    var id: String { cardId }
}

/// Listens for the branch items of the card menu ("Merge into main…") and opens
/// their sheets. A modifier of its own, like `MarkDoneReceiver`: ContentView's
/// `body` already carries so many `.onReceive` calls that one more makes the type
/// checker give up. Apply it once in the view tree, or each menu item opens two sheets.
struct BranchActionReceiver: ViewModifier {
    let store: BoardStore
    @State private var mergeTarget: BranchActionTarget?
    @State private var finishTarget: BranchActionTarget?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .kanbanCodeMergeIntoMain).receive(on: RunLoop.main)) { notification in
                guard let cardId = notification.userInfo?["cardId"] as? String else { return }
                mergeTarget = target(cardId: cardId, verb: "merge")
            }
            .onReceive(NotificationCenter.default.publisher(for: .kanbanCodeFinishBranch).receive(on: RunLoop.main)) { notification in
                guard let cardId = notification.userInfo?["cardId"] as? String else { return }
                finishTarget = target(cardId: cardId, verb: "finish")
            }
            .sheet(item: $mergeTarget) { target in
                MergeIntoMainSheet(target: target) { text in
                    store.dispatch(.setNotice(text, kind: .success))
                }
            }
            .sheet(item: $finishTarget) { target in
                FinishBranchSheet(target: target, store: store) { text in
                    store.dispatch(.setNotice(text, kind: .success))
                }
            }
    }

    /// The card's worktree and branch, or nil after a notice that says why there is none.
    private func target(cardId: String, verb: String) -> BranchActionTarget? {
        guard let card = store.state.cards.first(where: { $0.id == cardId }) else {
            KanbanCodeLog.warn("merge", "\(verb): card \(cardId) not found")
            store.dispatch(.setNotice("This card is no longer on the board; nothing to \(verb).", kind: .warning))
            return nil
        }
        guard let worktree = card.link.worktreeLink?.path, !worktree.isEmpty,
              let branch = card.link.worktreeLink?.branch, !branch.isEmpty else {
            store.dispatch(.setNotice("This card has no worktree branch to \(verb).", kind: .warning))
            return nil
        }
        return BranchActionTarget(cardId: cardId, worktreePath: worktree, branch: branch)
    }
}

// MARK: - Merge into main sheet

struct MergeIntoMainSheet: View {
    let target: BranchActionTarget
    /// Called with the result text when the merge went through; the sheet closes after it.
    let onMerged: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case loaded(MergePreflight)
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var carried: Set<String> = []
    @State private var isMerging = false
    /// The text of a refused merge. The sheet stays open so it can be read.
    @State private var refusal: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Merge into main")
                .font(.headline)
            Text(target.branch)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)

            content

            if let refusal {
                Text(refusal)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buttons
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled(isMerging)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the branch…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let text):
            Text(text)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded(let preflight):
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let lines = MergeSheetText.lines(for: preflight)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        lineView(line)
                    }
                    docChoices(preflight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 360)
            if let reason = preflight.blockReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("  ") {
            Text(line.dropFirst(2))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
        } else if line.hasPrefix("Warning") {
            Text(line)
                .foregroundStyle(.orange)
                .padding(.top, 6)
        } else {
            Text(line)
                .padding(.top, 6)
        }
    }

    /// One checkbox per documentation file that is not in main yet, all on to begin with.
    @ViewBuilder
    private func docChoices(_ preflight: MergePreflight) -> some View {
        let fresh = preflight.docs.filter { $0.state == .new }
        if !fresh.isEmpty, canMerge(preflight.relation) {
            Text("Documentation to copy into main")
                .padding(.top, 10)
            ForEach(fresh) { doc in
                Toggle(isOn: Binding(
                    get: { carried.contains(doc.path) },
                    set: { on in
                        if on { carried.insert(doc.path) } else { carried.remove(doc.path) }
                    }
                )) {
                    Text(doc.path)
                        .font(.system(.caption, design: .monospaced))
                }
                .toggleStyle(.checkbox)
                .disabled(isMerging)
            }
        }
    }

    private func canMerge(_ relation: BranchRelation) -> Bool {
        switch relation {
        case .fastForward, .upToDate: return true
        case .diverged, .mainNotOnMain: return false
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            if isMerging { ProgressView().controlSize(.small) }
            if case .failed = phase {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isMerging)
                Button("Merge") { startMerge() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!mergeEnabled)
            }
        }
    }

    private var mergeEnabled: Bool {
        guard !isMerging, case .loaded(let preflight) = phase else { return false }
        return preflight.blockReason == nil
    }

    // MARK: Actions

    /// `BranchMerge` is a Sendable struct with nonisolated async methods, so the
    /// git calls run off the main actor; only the state updates below run on it.
    private func load(keepChoices: Bool = false) async {
        do {
            let preflight = try await BranchMerge().preflight(worktreePath: target.worktreePath, branch: target.branch)
            let fresh = Set(preflight.docs.filter { $0.state == .new }.map(\.path))
            // A reload after a refusal keeps the boxes the user unticked.
            if keepChoices { carried.formIntersection(fresh) } else { carried = fresh }
            phase = .loaded(preflight)
        } catch {
            KanbanCodeLog.warn("merge", "preflight failed for \(target.branch): \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    private func startMerge() {
        guard case .loaded(let preflight) = phase else { return }
        let docs = preflight.docs.filter { $0.state == .new && carried.contains($0.path) }.map(\.path)
        refusal = nil
        isMerging = true
        Task {
            let outcome = await BranchMerge().merge(worktreePath: target.worktreePath, branch: target.branch, carryDocs: docs)
            isMerging = false
            if case .refused = outcome {
                refusal = MergeSheetText.resultNotice(outcome)
                // The refusal may mean the state changed; show what it is now,
                // with Merge off until the check is back.
                phase = .loading
                await load(keepChoices: true)
            } else {
                onMerged(MergeSheetText.resultNotice(outcome))
                dismiss()
            }
        }
    }
}

// MARK: - Finish: steps and text

enum FinishStep: Equatable {
    case closeCard, removeWorktree, rebuildApp
}

/// The decisions of the Finish sheet that do not need a view.
enum FinishPlan {
    /// The checked steps, always in the order close, remove, rebuild.
    static func steps(closeCard: Bool, removeWorktree: Bool, rebuild: Bool) -> [FinishStep] {
        var out: [FinishStep] = []
        if closeCard { out.append(.closeCard) }
        if removeWorktree { out.append(.removeWorktree) }
        if rebuild { out.append(.rebuildApp) }
        return out
    }

    /// The cards other than this one that use `branch`. `counts` is
    /// `AppState.activeWorktreeBranchCounts`, which counts every card that is not
    /// archived, this one included; an archived card is not in it.
    static func otherActiveCardsOnBranch(counts: [String: Int], branch: String, cardIsActive: Bool) -> Int {
        max(0, counts[branch, default: 0] - (cardIsActive ? 1 : 0))
    }

    /// Why the worktree cannot be removed, or nil. With `closeCard` the session of
    /// the card is stopped before the removal, so a live session is not a reason yet;
    /// the run checks again after the close.
    static func removalBlockReason(
        state: FinishState,
        worktreePath: String,
        appBundlePath: String,
        hasLiveSession: Bool,
        closeCard: Bool,
        otherActiveCardsOnBranch: Int
    ) -> String? {
        WorktreeRemovalGuard.blockReason(
            branchMerged: state.branchMerged,
            worktreePath: worktreePath,
            appBundlePath: appBundlePath,
            hasLiveSession: hasLiveSession && !closeCard,
            otherActiveCardsOnBranch: otherActiveCardsOnBranch)
    }
}

enum FinishSheetText {
    /// What the Remove worktree step says it will delete.
    static func removeLine(for s: FinishState) -> String {
        guard !s.ignored.isEmpty else { return "Removes the worktree; no ignored files are deleted with it." }
        let onlyFolders = s.ignored.allSatisfy { $0.path.hasSuffix("/") }
        let noun = onlyFolders ? "ignored folder" : "ignored path"
        let list = s.ignored.map { entry in
            entry.path.hasSuffix("/") ? "\(entry.path) (\(MergeSheetText.count(entry.fileCount, "file")))" : entry.path
        }.joined(separator: ", ")
        return "Deletes \(MergeSheetText.count(s.ignored.count, noun)): \(list)"
    }

    /// What a finished step says in the closing notice.
    static func stepDone(_ step: FinishStep) -> String {
        switch step {
        case .closeCard: return "Card closed"
        case .removeWorktree: return "Worktree removed"
        case .rebuildApp:
            return "App built; to run it, quit the running copy and open build/KanbanCode.app"
        }
    }

    static func summary(done: [FinishStep]) -> String {
        guard !done.isEmpty else { return "Nothing to do." }
        return done.enumerated().map { index, step in
            let text = stepDone(step)
            return index == 0 ? text : text.prefix(1).lowercased() + text.dropFirst()
        }.joined(separator: "; ")
    }

    static func running(_ step: FinishStep) -> String {
        switch step {
        case .closeCard: return "Closing the card…"
        case .removeWorktree: return "Removing the worktree…"
        case .rebuildApp: return "Building the app with make app; this can take minutes…"
        }
    }
}

// MARK: - Finish branch sheet

/// Three steps after a branch is merged: close the card, remove the worktree,
/// rebuild the app. All off to begin with; Finish runs the ticked ones in that order.
struct FinishBranchSheet: View {
    let target: BranchActionTarget
    let store: BoardStore
    /// Called with the closing text when every step went through; the sheet closes after it.
    let onFinished: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private struct Loaded {
        var state: FinishState
        var hasAppTarget: Bool
    }

    private enum Phase {
        case loading
        case loaded(Loaded)
        /// Git could not say (for example the main checkout is not on main); every step stays off.
        case failed(String)
    }

    private struct StepFailure {
        var text: String
        var output: String?
    }

    @State private var phase: Phase = .loading
    @State private var closeCard = false
    @State private var removeWorktree = false
    @State private var rebuild = false
    @State private var running: FinishStep?
    /// Steps that went through, kept across a retry after a failed step.
    @State private var done: [FinishStep] = []
    @State private var failure: StepFailure?

    private var link: Link? { store.state.links[target.cardId] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish branch")
                .font(.headline)
            Text(target.branch)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)

            content

            if let failure {
                if !done.isEmpty {
                    Text("Done before the failure: \(FinishSheetText.summary(done: done))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(failure.text)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let output = failure.output, !output.isEmpty {
                    ScrollView {
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }

            buttons
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled(running != nil)
        .task { await load() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the branch…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let text):
            Text(text)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            stepRow("Close card", detail: nil, isOn: .constant(false), enabled: false)
            stepRow("Remove worktree", detail: nil, isOn: .constant(false), enabled: false)
            stepRow("Rebuild app", detail: nil, isOn: .constant(false), enabled: false)
        case .loaded(let loaded):
            if link == nil {
                Text("This card is no longer on the board.")
                    .foregroundStyle(.orange)
            }
            stepRow(closeTitle, detail: nil, isOn: binding(.closeCard, $closeCard), enabled: stepsEnabled(.closeCard))

            let reason = removalReason(loaded)
            stepRow(
                "Remove worktree",
                detail: reason ?? FinishSheetText.removeLine(for: loaded.state),
                detailIsWarning: reason != nil,
                isOn: Binding(
                    get: { done.contains(.removeWorktree) || (removeWorktree && reason == nil) },
                    set: { removeWorktree = $0 }),
                enabled: stepsEnabled(.removeWorktree) && reason == nil)

            if loaded.hasAppTarget {
                stepRow(
                    "Rebuild app",
                    detail: "Runs make app in the main checkout. It only builds: the running app is not restarted.",
                    isOn: binding(.rebuildApp, $rebuild),
                    enabled: stepsEnabled(.rebuildApp))
            }

            if let running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(FinishSheetText.running(running))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var closeTitle: String {
        guard link?.tmuxLink != nil, !done.contains(.closeCard) else { return "Close card" }
        return "Close card (stops its running terminals)"
    }

    private func binding(_ step: FinishStep, _ flag: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { done.contains(step) || flag.wrappedValue }, set: { flag.wrappedValue = $0 })
    }

    private func stepsEnabled(_ step: FinishStep) -> Bool {
        running == nil && !done.contains(step) && link != nil
    }

    private func stepRow(
        _ title: String, detail: String?, detailIsWarning: Bool = false, isOn: Binding<Bool>, enabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
                .disabled(!enabled)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(detailIsWarning ? Color.orange : Color.secondary)
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    /// Why the worktree cannot be removed now, or nil. With Close card ticked the
    /// session is stopped first, so a live session is ignored here; the run checks
    /// again after the close.
    private func removalReason(_ loaded: Loaded) -> String? {
        guard !done.contains(.removeWorktree) else { return nil }
        guard let link else { return "This card is no longer on the board." }
        return FinishPlan.removalBlockReason(
            state: loaded.state,
            worktreePath: target.worktreePath,
            appBundlePath: Bundle.main.bundlePath,
            hasLiveSession: link.tmuxLink != nil,
            closeCard: closeCard && !done.contains(.closeCard),
            otherActiveCardsOnBranch: FinishPlan.otherActiveCardsOnBranch(
                counts: store.state.activeWorktreeBranchCounts,
                branch: target.branch,
                cardIsActive: !link.manuallyArchived))
    }

    // MARK: Buttons

    /// The steps Finish would run now.
    private var pendingSteps: [FinishStep] {
        guard case .loaded(let loaded) = phase, link != nil else { return [] }
        return FinishPlan.steps(
            closeCard: closeCard && !done.contains(.closeCard),
            removeWorktree: removeWorktree && removalReason(loaded) == nil && !done.contains(.removeWorktree),
            rebuild: rebuild && loaded.hasAppTarget && !done.contains(.rebuildApp))
    }

    private var buttons: some View {
        HStack {
            Spacer()
            if running != nil { ProgressView().controlSize(.small) }
            if case .failed = phase {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(running != nil)
                Button("Finish") { startFinish() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(running != nil || pendingSteps.isEmpty)
            }
        }
    }

    // MARK: Actions

    /// `BranchFinish` is a Sendable struct with nonisolated async methods, so git and
    /// make run off the main actor; only the state updates below run on it.
    private func load() async {
        do {
            let state = try await BranchFinish().state(worktreePath: target.worktreePath, branch: target.branch)
            phase = .loaded(Loaded(state: state, hasAppTarget: BranchFinish().hasAppTarget(mainCheckout: state.mainCheckout)))
        } catch {
            KanbanCodeLog.warn("merge", "finish state failed for \(target.branch): \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    private func startFinish() {
        guard case .loaded(let loaded) = phase else { return }
        let steps = pendingSteps
        guard !steps.isEmpty else { return }
        failure = nil
        Task { await run(steps, loaded: loaded) }
    }

    /// Runs the steps in order and stops at the first one that fails. The guard for
    /// the removal is evaluated here, right before `git worktree remove`, on fresh
    /// state: the sheet may have been open for a while, and the close just changed things.
    private func run(_ steps: [FinishStep], loaded: Loaded) async {
        var mainCheckout = loaded.state.mainCheckout
        // Taken before the close: the close clears the link, and these names are
        // what is checked against tmux afterwards.
        let sessions = link?.tmuxLink?.allSessionNames ?? []
        var closedHere = false

        for step in steps {
            running = step
            switch step {
            case .closeCard:
                // Pressing Finish is the confirmation; the card has no dialog of its own here.
                await store.dispatchAndWait(.markCardDone(cardId: target.cardId))
                closedHere = true

            case .removeWorktree:
                if closedHere, !sessions.isEmpty { await Self.waitForSessionsToEnd(sessions) }
                guard let link else { return fail("This card is no longer on the board; the worktree was not removed.") }
                let fresh: FinishState
                do {
                    fresh = try await BranchFinish().state(worktreePath: target.worktreePath, branch: target.branch)
                } catch {
                    return fail(error.localizedDescription)
                }
                mainCheckout = fresh.mainCheckout
                // The state after the close, as it is now: the link, and tmux itself.
                let stillRunning = await !Self.runningSessions(among: sessions).isEmpty
                if let reason = FinishPlan.removalBlockReason(
                    state: fresh,
                    worktreePath: target.worktreePath,
                    appBundlePath: Bundle.main.bundlePath,
                    hasLiveSession: link.tmuxLink != nil || stillRunning,
                    closeCard: false,
                    otherActiveCardsOnBranch: FinishPlan.otherActiveCardsOnBranch(
                        counts: store.state.activeWorktreeBranchCounts,
                        branch: target.branch,
                        cardIsActive: !link.manuallyArchived)
                ) {
                    return fail(reason)
                }
                if case .failure(let error) = await BranchFinish().removeWorktree(mainCheckout: mainCheckout, worktreePath: target.worktreePath) {
                    return fail(error.localizedDescription)
                }

            case .rebuildApp:
                let result = await BranchFinish().rebuildApp(mainCheckout: mainCheckout)
                guard result.ok else {
                    return fail("make app failed; the end of its output:", output: result.outputTail)
                }
            }
            done.append(step)
            KanbanCodeLog.info("merge", "finish \(target.branch): \(FinishSheetText.stepDone(step))")
        }

        running = nil
        onFinished(FinishSheetText.summary(done: done))
        dismiss()
    }

    private func fail(_ text: String, output: String? = nil) {
        KanbanCodeLog.warn("merge", "finish \(target.branch) stopped: \(text)")
        failure = StepFailure(text: text, output: output)
        running = nil
    }

    // MARK: tmux

    /// Names of `names` that tmux still lists. When tmux cannot be asked, all of them,
    /// so an unknown state is never taken for a stopped session.
    private nonisolated static func runningSessions(among names: [String]) async -> [String] {
        guard !names.isEmpty else { return [] }
        do {
            let live = Set(try await AppServices.tmux.listSessions().map(\.name))
            return names.filter { live.contains($0) }
        } catch {
            KanbanCodeLog.warn("merge", "could not list tmux sessions: \(error.localizedDescription)")
            return names
        }
    }

    /// Waits up to 10 s for the sessions to be gone; the kill runs as an effect and
    /// the caller checks the result itself.
    private nonisolated static func waitForSessionsToEnd(_ names: [String]) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await runningSessions(among: names).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
