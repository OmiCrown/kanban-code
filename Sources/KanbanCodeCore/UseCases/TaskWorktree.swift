import Foundation

/// The value of `--worktree` for a task started from the New Task dialog.
public enum TaskWorktree {
    /// nil: no worktree flag. Empty: `--worktree` alone, and the assistant
    /// picks a random name. Otherwise the name the user typed.
    public static func flagName(create: Bool, supported: Bool, typed: String?) -> String? {
        guard create, supported else { return nil }
        return typed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
