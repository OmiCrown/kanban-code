import SwiftUI
import KanbanCodeCore

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

    private static func count(_ n: Int, _ noun: String) -> String {
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

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .kanbanCodeMergeIntoMain).receive(on: RunLoop.main)) { notification in
                guard let cardId = notification.userInfo?["cardId"] as? String else { return }
                mergeTarget = target(cardId: cardId)
            }
            .sheet(item: $mergeTarget) { target in
                MergeIntoMainSheet(target: target) { text in
                    store.dispatch(.setNotice(text, kind: .success))
                }
            }
    }

    /// The card's worktree and branch, or nil after a notice that says why there is none.
    private func target(cardId: String) -> BranchActionTarget? {
        guard let card = store.state.cards.first(where: { $0.id == cardId }) else { return nil }
        guard let worktree = card.link.worktreeLink?.path, !worktree.isEmpty,
              let branch = card.link.worktreeLink?.branch, !branch.isEmpty else {
            store.dispatch(.setNotice("This card has no worktree branch to merge.", kind: .warning))
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
    private func load() async {
        do {
            let preflight = try await BranchMerge().preflight(worktreePath: target.worktreePath, branch: target.branch)
            let fresh = Set(preflight.docs.filter { $0.state == .new }.map(\.path))
            // A reload after a refusal keeps the boxes the user unticked.
            if case .loaded = phase { carried.formIntersection(fresh) } else { carried = fresh }
            phase = .loaded(preflight)
        } catch {
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
                // The refusal may mean the state changed; show what it is now.
                await load()
            } else {
                onMerged(MergeSheetText.resultNotice(outcome))
                dismiss()
            }
        }
    }
}
