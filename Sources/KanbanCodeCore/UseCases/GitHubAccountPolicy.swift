import Foundation

/// Which GitHub account a repository is worked on as, and whether the
/// repository belongs where it lies. A repository belongs to the profile whose
/// `projectRoots` contain it (the longest match wins). A repository outside
/// every root is not managed: nothing is checked and `gh` keeps its active account.
public enum GitHubAccountPolicy {
    public enum Verdict: Equatable, Sendable {
        /// No profile claims the repository.
        case unmanaged
        /// Claimed, and the owner is allowed (or the profile has no owner list).
        case allowed(profilePath: String, githubUser: String?)
        /// Claimed, but `owner` is not in the profile's list: a repository of
        /// another account in this profile's folder.
        case foreignOwner(profilePath: String, profileName: String, owner: String)
    }

    /// The profile whose root contains `repoPath`; the longest root wins.
    public static func profile(forRepoPath repoPath: String, in profiles: [ClaudeProfile]) -> ClaudeProfile? {
        let repo = ClaudeProfile.normalized(repoPath)
        var best: (profile: ClaudeProfile, length: Int)?
        for profile in profiles {
            for root in profile.projectRoots where repo == root || repo.hasPrefix(root + "/") {
                if root.count > (best?.length ?? -1) { best = (profile, root.count) }
            }
        }
        return best?.profile
    }

    /// `owner` is the GitHub owner of the repository's remote, nil when it has none.
    public static func verdict(repoPath: String, owner: String?, profiles: [ClaudeProfile]) -> Verdict {
        guard let profile = profile(forRepoPath: repoPath, in: profiles) else { return .unmanaged }
        guard let owner, !owner.isEmpty, !profile.githubOwners.isEmpty else {
            return .allowed(profilePath: profile.path, githubUser: profile.githubUser)
        }
        let allowed = Set((profile.githubOwners + [profile.githubUser].compactMap { $0 }).map { $0.lowercased() })
        if allowed.contains(owner.lowercased()) {
            return .allowed(profilePath: profile.path, githubUser: profile.githubUser)
        }
        return .foreignOwner(profilePath: profile.path, profileName: profile.name, owner: owner)
    }
}
