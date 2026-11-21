import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("Claude launcher resolver")
struct ClaudeLauncherResolverTests {
    private func profile(roots: [String], launcherId: String?) -> ClaudeProfile {
        ClaudeProfile(path: "/h/.claude-x", projectRoots: roots, launcherId: launcherId, home: "/h")
    }

    @Test func defaultFollowsProfileRoot() {
        let profiles = [profile(roots: ["/r/omi"], launcherId: "codemie")]
        #expect(ClaudeLauncherResolver.defaultCommand(
            forProjectPath: "/r/omi/app", profiles: profiles, launchers: [.codemie]) == "codemie-claude")
    }

    @Test func outsideEveryRootIsPlain() {
        let profiles = [profile(roots: ["/r/omi"], launcherId: "codemie")]
        #expect(ClaudeLauncherResolver.defaultCommand(
            forProjectPath: "/elsewhere/app", profiles: profiles, launchers: [.codemie]) == "claude")
    }

    @Test func profileWithoutLauncherIsPlain() {
        let profiles = [profile(roots: ["/r/omi"], launcherId: nil)]
        #expect(ClaudeLauncherResolver.defaultCommand(
            forProjectPath: "/r/omi/app", profiles: profiles, launchers: [.codemie]) == "claude")
    }

    @Test func danglingLauncherIdIsPlain() {
        let profiles = [profile(roots: ["/r/omi"], launcherId: "gone")]
        #expect(ClaudeLauncherResolver.defaultCommand(
            forProjectPath: "/r/omi/app", profiles: profiles, launchers: [.codemie]) == "claude")
    }

    @Test func nilProjectPathIsPlain() {
        let profiles = [profile(roots: ["/r/omi"], launcherId: "codemie")]
        #expect(ClaudeLauncherResolver.defaultCommand(
            forProjectPath: nil, profiles: profiles, launchers: [.codemie]) == "claude")
    }

    @Test func longestRootWins() {
        let profiles = [
            ClaudeProfile(path: "/h/.claude-a", projectRoots: ["/r"], launcherId: "codemie", home: "/h"),
            ClaudeProfile(path: "/h/.claude-b", projectRoots: ["/r/client"], launcherId: nil, home: "/h"),
        ]
        #expect(ClaudeLauncherResolver.defaultCommand(
            forProjectPath: "/r/client/x", profiles: profiles, launchers: [.codemie]) == "claude")
    }

    @Test func commandToStoreDropsPlain() {
        #expect(ClaudeLauncherResolver.commandToStore("claude") == nil)
        #expect(ClaudeLauncherResolver.commandToStore(" codemie-claude ") == "codemie-claude")
    }

    @Test func editedTextKeepsKnownToken() {
        #expect(ClaudeLauncherResolver.command(
            fromEdited: "FOO=1 langwatch codemie-claude --resume x", launchers: [.codemie]) == "codemie-claude")
        #expect(ClaudeLauncherResolver.command(fromEdited: "~/bin/mytool --x", launchers: [.codemie]) == "claude")
        #expect(ClaudeLauncherResolver.command(fromEdited: "", launchers: [.codemie]) == "claude")
    }

    @Test func forLaunchPrecedence() {
        let profiles = [profile(roots: ["/r/omi"], launcherId: "codemie")]
        func resolve(explicit: String? = nil, link: String? = nil, session: Bool = false) -> String {
            ClaudeLauncherResolver.forLaunch(
                explicit: explicit, linkLauncherCommand: link, hasSession: session,
                projectPath: "/r/omi/app", profiles: profiles, launchers: [.codemie])
        }
        #expect(resolve(explicit: "claude", link: "codemie-claude", session: true) == "claude")
        #expect(resolve(link: "codemie-claude", session: true) == "codemie-claude")
        #expect(resolve() == "codemie-claude")
        // A session that was started before launchers existed keeps plain `claude`.
        #expect(resolve(session: true) == "claude")
    }
}
