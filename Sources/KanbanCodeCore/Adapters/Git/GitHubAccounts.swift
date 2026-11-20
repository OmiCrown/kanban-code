import Foundation

/// The GitHub account `gh` acts as in a repository, by the profile whose
/// folder the repository lies in (`GitHubAccountPolicy`). One shared instance,
/// because every `GhCliAdapter` must agree on it.
///
/// - A managed repository with an allowed owner runs `gh` with that profile's
///   token (`gh auth token --user <githubUser>`), kept for a while.
/// - A repository outside every profile folder, or of a profile without a
///   `githubUser`, runs as the account `gh` has active, as before.
/// - A repository whose owner is not in the profile's list is a problem, and a
///   merge there is refused.
public final class GitHubAccounts: @unchecked Sendable {
    public static let shared = GitHubAccounts()

    public enum Problem: Equatable, Sendable, CustomStringConvertible {
        /// The repository's owner is not one of the profile's owners.
        case foreignOwner(profileName: String, owner: String, allowed: [String])
        /// `gh` has no token for the login the profile works as.
        case noToken(profileName: String, githubUser: String)

        public var description: String {
            switch self {
            case .foreignOwner(let profile, let owner, let allowed):
                "This repository belongs to \(owner), which is not one of the owners of the \(profile) profile (\(allowed.joined(separator: ", "))). It lies in that profile's folder: move it or add the owner to the profile."
            case .noToken(let profile, let user):
                "gh has no login for \(user), the GitHub account of the \(profile) profile. Run: gh auth login, then sign in as \(user)."
            }
        }
    }

    public typealias FetchToken = @Sendable (_ user: String) async -> String?

    private let lock = NSLock()
    private var profiles: [ClaudeProfile] = []
    private let tokens: TokenCache

    public init(lifetime: TimeInterval = 600, retryAfter: TimeInterval = 60, fetchToken: FetchToken? = nil) {
        tokens = TokenCache(lifetime: lifetime, retryAfter: retryAfter, fetch: fetchToken ?? Self.ghAuthToken)
    }

    /// Takes effect on the next `gh` call.
    public func setProfiles(_ profiles: [ClaudeProfile]) {
        lock.withLock { self.profiles = profiles }
    }

    private var current: [ClaudeProfile] { lock.withLock { profiles } }

    /// What is wrong with running a mutating command in `repoPath`, or nil.
    /// `owner` is the GitHub owner of the repository's remote.
    public func problem(forRepo repoPath: String, owner: String?, now: Date = Date()) async -> Problem? {
        let profiles = current
        switch GitHubAccountPolicy.verdict(repoPath: repoPath, owner: owner, profiles: profiles) {
        case .unmanaged:
            return nil
        case .foreignOwner(let path, let name, let owner):
            let profile = profiles.first { $0.path == path }
            let allowed = ((profile?.githubOwners ?? []) + [profile?.githubUser].compactMap { $0 })
            return .foreignOwner(profileName: name, owner: owner, allowed: allowed)
        case .allowed(let path, let user):
            guard let user, await tokens.token(for: user, now: now) == nil else { return nil }
            let name = profiles.first { $0.path == path }?.name ?? path
            return .noToken(profileName: name, githubUser: user)
        }
    }

    /// The environment for `gh` in `repoPath`: the login environment plus the
    /// profile's `GH_TOKEN`. Nil leaves `gh` as it is (its active account).
    public func environment(forRepo repoPath: String, now: Date = Date()) async -> [String: String]? {
        guard let profile = GitHubAccountPolicy.profile(forRepoPath: repoPath, in: current),
              let user = profile.githubUser,
              let token = await tokens.token(for: user, now: now) else { return nil }
        var env = ShellCommand.loginEnvironment
        env["GH_TOKEN"] = token
        env.removeValue(forKey: "GITHUB_TOKEN")
        return env
    }

    /// Whether a managed repository should not be asked as the profile's
    /// account: its owner is not allowed.
    public func isForeign(repoPath: String, owner: String?) -> Bool {
        if case .foreignOwner = GitHubAccountPolicy.verdict(repoPath: repoPath, owner: owner, profiles: current) {
            return true
        }
        return false
    }

    static func ghAuthToken(user: String) async -> String? {
        guard let gh = ShellCommand.findExecutable("gh") else { return nil }
        var env = ShellCommand.loginEnvironment
        // Set, these make `gh auth token` print them instead of the stored login.
        env.removeValue(forKey: "GH_TOKEN")
        env.removeValue(forKey: "GITHUB_TOKEN")
        guard let result = try? await ShellCommand.run(
            gh, arguments: ["auth", "token", "--hostname", "github.com", "--user", user],
            environment: env, timeout: 20),
              result.succeeded else { return nil }
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

/// Tokens by login. A found token is reused for `lifetime`; a login with no
/// token is left alone for `retryAfter`, so a missing login does not run `gh`
/// on every poll. Callers that arrive during a fetch wait for it.
private actor TokenCache {
    private let fetch: GitHubAccounts.FetchToken
    private let lifetime: TimeInterval
    private let retryAfter: TimeInterval
    private var tokens: [String: (token: String?, at: Date)] = [:]
    private var fetching: [String: Task<String?, Never>] = [:]

    init(lifetime: TimeInterval, retryAfter: TimeInterval, fetch: @escaping GitHubAccounts.FetchToken) {
        self.lifetime = lifetime
        self.retryAfter = retryAfter
        self.fetch = fetch
    }

    func token(for user: String, now: Date) async -> String? {
        let key = user.lowercased()
        if let cached = tokens[key], now.timeIntervalSince(cached.at) < (cached.token == nil ? retryAfter : lifetime) {
            return cached.token
        }
        if let running = fetching[key] { return await running.value }
        let fetch = self.fetch
        let task = Task { await fetch(user) }
        fetching[key] = task
        let token = await task.value
        fetching[key] = nil
        if token == nil {
            KanbanCodeLog.warn("github", "No gh token for \(user) (gh auth login)")
        }
        tokens[key] = (token, now)
        return token
    }
}
