import Foundation

/// Discovers Claude Code sessions in every enabled profile (`~/.claude`,
/// `~/.claude-*`) and merges them into one list.
///
/// It holds one `ClaudeCodeSessionDiscovery` per enabled profile whose folder
/// exists, so each profile keeps its own directory and file mtime caches. A
/// disabled or missing profile is never read, and its discovery (with its
/// cache) is dropped. An empty profile list reads `~/.claude` only, which is
/// what the app did before profiles existed.
public final class ProfileSessionDiscovery: SessionDiscovery, @unchecked Sendable {
    private let lock = NSLock()
    private var profiles: [ClaudeProfile]
    /// Profile path → its discovery, created on demand.
    private var discoveries: [String: ClaudeCodeSessionDiscovery] = [:]
    private var headlessExclusion: PathExclusion = .none

    private let home: String

    public init(profiles: [ClaudeProfile] = [], home: String = NSHomeDirectory()) {
        self.profiles = profiles
        self.home = home
    }

    /// Replaces the profile list. Thread-safe; takes effect on the next scan.
    public func setProfiles(_ profiles: [ClaudeProfile]) {
        lock.lock()
        defer { lock.unlock() }
        self.profiles = profiles
        let active = Set(activeProfiles().map(\.path))
        for path in discoveries.keys where !active.contains(path) {
            discoveries.removeValue(forKey: path)
        }
    }

    public func setHeadlessExclusion(_ exclusion: PathExclusion) {
        lock.lock()
        defer { lock.unlock() }
        headlessExclusion = exclusion
        for discovery in discoveries.values {
            discovery.setHeadlessExclusion(exclusion)
        }
    }

    public func discoverSessions() async throws -> [Session] {
        try await scan { try await $0.discoverSessions() }
    }

    public func discoverNewOrModified(since: Date) async throws -> [Session] {
        try await scan { try await $0.discoverNewOrModified(since: since) }
    }

    // MARK: - Private

    /// Enabled profiles whose folder exists. Caller holds the lock.
    private func activeProfiles() -> [ClaudeProfile] {
        let list = profiles.isEmpty ? [ClaudeProfile(path: "~/.claude", enabled: true, integration: true)] : profiles
        return list.filter { $0.enabled && $0.exists && $0.isSafeLocation(home: home) }
    }

    /// One discovery per active profile, created on demand. The scan itself
    /// runs outside the lock.
    private func currentDiscoveries() -> [ClaudeCodeSessionDiscovery] {
        lock.lock()
        defer { lock.unlock() }
        let active = activeProfiles()
        let activePaths = Set(active.map(\.path))
        for path in discoveries.keys where !activePaths.contains(path) {
            discoveries.removeValue(forKey: path)
        }
        return active.map { profile in
            if let existing = discoveries[profile.path] { return existing }
            let discovery = ClaudeCodeSessionDiscovery(claudeDir: profile.projectsDirectory)
            discovery.setHeadlessExclusion(headlessExclusion)
            discoveries[profile.path] = discovery
            return discovery
        }
    }

    private func scan(
        _ read: (ClaudeCodeSessionDiscovery) async throws -> [Session]
    ) async throws -> [Session] {
        var byId: [String: Session] = [:]
        for discovery in currentDiscoveries() {
            for session in try await read(discovery) {
                if let other = byId[session.id] {
                    // One id in two profiles is not expected: the newer
                    // transcript represents the session.
                    KanbanCodeLog.warn(
                        "profiles",
                        "session \(session.id) found in two profiles: \(other.configDirectory ?? "?") and \(session.configDirectory ?? "?")")
                    if session.modifiedTime > other.modifiedTime { byId[session.id] = session }
                } else {
                    byId[session.id] = session
                }
            }
        }
        return byId.values.sorted { $0.modifiedTime > $1.modifiedTime }
    }
}
