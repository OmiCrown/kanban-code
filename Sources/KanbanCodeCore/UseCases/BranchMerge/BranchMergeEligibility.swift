import Foundation

/// Whether a card offers "Merge into main" and "Finish branch": a local card
/// in a project that merges without a PR, with a worktree other than the main
/// checkout.
public enum BranchMergeEligibility {
    public static func offered(for link: Link, mergesWithoutPR: Bool) -> Bool {
        guard mergesWithoutPR else { return false }
        // A card on a remote or boxd machine has its checkout there, not here.
        guard !link.isRemote, link.remote == nil else { return false }
        guard let worktree = link.worktreePath, !worktree.isEmpty else { return false }
        guard let project = link.projectPath, !project.isEmpty else { return true }
        return (worktree as NSString).standardizingPath != (project as NSString).standardizingPath
    }
}
