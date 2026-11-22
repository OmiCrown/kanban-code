import SwiftUI
import AppKit
import KanbanCodeCore

/// About window: which build this is (version, branch, worktree, commit, build date) and whether it
/// is behind the local sources it was made from. Reads only; nothing is dispatched.
struct AboutView: View {
    private let info = BuildInfo(infoDictionary: Bundle.main.infoDictionary)
    @State private var freshness: BuildFreshness?
    @State private var checking = true

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Kanban Code")
                .font(.title2.weight(.semibold))

            if let info {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("Version", info.describe)
                    row("Branch", info.branch)
                    row("Worktree", info.worktree)
                    row("Commit", info.commitText)
                    row("Built", info.buildDateText())
                    if info.canCheckFreshness {
                        row("Sources", checking ? "Checking…" : freshness?.text)
                    }
                }
                .textSelection(.enabled)

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(info.summaryText(freshness: freshness), forType: .string)
                }
            } else {
                Text(BuildInfo.devRunText)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 380)
        .task {
            guard let info, info.canCheckFreshness else { return }
            freshness = await BuildFreshness.check(info)
            checking = false
        }
    }

    /// A row is left out when its value is missing.
    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(label)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(value)
                    .gridColumnAlignment(.leading)
            }
        }
    }
}
