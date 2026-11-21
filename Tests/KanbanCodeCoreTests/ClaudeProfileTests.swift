import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ClaudeProfile")
struct ClaudeProfileTests {
    private let home = "/Users/test"

    private func makeHome(_ dirs: [String], files: [String] = []) throws -> String {
        let root = NSTemporaryDirectory() + "claude-profile-" + UUID().uuidString
        let fm = FileManager.default
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        for dir in dirs {
            try fm.createDirectory(atPath: root + "/" + dir, withIntermediateDirectories: true)
        }
        for file in files {
            fm.createFile(atPath: root + "/" + file, contents: Data("{}".utf8))
        }
        return root
    }

    @Test func defaultNames() {
        #expect(ClaudeProfile.defaultName(forPath: "/h/.claude") == "default")
        #expect(ClaudeProfile.defaultName(forPath: "/h/.claude-Client") == "Client")
        #expect(ClaudeProfile.defaultName(forPath: "/h/other-dir") == "other-dir")
    }

    @Test func normalizesPaths() {
        #expect(ClaudeProfile.normalized("~/.claude-X/", home: home) == "/Users/test/.claude-X")
        #expect(ClaudeProfile.normalized("/Users/test/.claude-X", home: home) == "/Users/test/.claude-X")
        #expect(ClaudeProfile.normalized("~", home: home) == "/Users/test")
    }

    @Test func discoverFindsProfilesWithProjects() throws {
        let h = try makeHome(
            [".claude/projects", ".claude-A/projects", ".claude-old"],
            files: [".claude.json"])
        let found = ClaudeProfile.discover(home: h)
        #expect(found == [h + "/.claude", h + "/.claude-A"])
    }

    @Test func mergedAddsNewProfilesOff() {
        let result = ClaudeProfile.merged(stored: [], found: ["/Users/test/.claude-A"], home: home)
        let a = result.first { $0.path == "/Users/test/.claude-A" }
        #expect(a?.enabled == false)
        #expect(a?.integration == false)
        #expect(a?.name == "A")
    }

    @Test func mergedKeepsMissingStored() {
        let stored = ClaudeProfile(path: "/Users/test/.claude-gone", enabled: true, integration: true, home: home)
        let result = ClaudeProfile.merged(stored: [stored], found: [], home: home)
        #expect(result.contains(stored))
        #expect(result.first { $0.path == stored.path }?.exists == false)
    }

    @Test func mergedForcesDefaultOn() {
        let stored = ClaudeProfile(path: "/Users/test/.claude", enabled: false, integration: false, home: home)
        let result = ClaudeProfile.merged(stored: [stored], found: [], home: home)
        #expect(result.first { $0.path == "/Users/test/.claude" }?.enabled == true)
        #expect(result.first { $0.path == "/Users/test/.claude" }?.integration == false)
    }

    @Test func mergedAddsDefaultWhenAbsent() {
        let result = ClaudeProfile.merged(stored: [], found: [], home: home)
        #expect(result.count == 1)
        #expect(result[0].path == "/Users/test/.claude")
        #expect(result[0].enabled)
        #expect(result[0].integration)
    }

    @Test func mergedDoesNotDuplicateStoredProfile() {
        let stored = ClaudeProfile(path: "/Users/test/.claude-A", enabled: true, home: home)
        let result = ClaudeProfile.merged(
            stored: [stored], found: ["/Users/test/.claude-A/"], home: home)
        #expect(result.filter { $0.path == "/Users/test/.claude-A" }.count == 1)
        #expect(result.first { $0.path == "/Users/test/.claude-A" }?.enabled == true)
    }

    @Test func transcriptToConfigDirectory() {
        #expect(ClaudeProfile.configDirectory(ofTranscript: "/h/.claude-X/projects/-a-b/id.jsonl") == "/h/.claude-X")
        #expect(ClaudeProfile.configDirectory(ofTranscript: "/h/.claude/projects/-a/id.jsonl") == "/h/.claude")
        #expect(ClaudeProfile.configDirectory(ofTranscript: "/tmp/x.jsonl") == nil)
        #expect(ClaudeProfile.configDirectory(ofTranscript: "/projects/-a/id.jsonl") == nil)
    }

    @Test func settingsDecodeWithoutKey() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(settings.claudeProfiles.isEmpty)
    }

    @Test func badProfileValueDoesNotDropSettings() throws {
        let json = """
        {"hasCompletedOnboarding": true,
         "claudeProfiles": [
           {"path": "/Users/test/.claude-A", "enabled": "yes", "integration": true},
           {"name": "no path"},
           {"path": "/Users/test/.claude-B", "enabled": true}
         ]}
        """
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.hasCompletedOnboarding)
        #expect(settings.claudeProfiles.map(\.path) == ["/Users/test/.claude-A", "/Users/test/.claude-B"])
        #expect(settings.claudeProfiles[0].enabled == false)
        #expect(settings.claudeProfiles[0].integration == true)
        #expect(settings.claudeProfiles[1].enabled == true)
    }

    @Test func profilesRoundTrip() throws {
        var settings = Settings()
        settings.claudeProfiles = [
            ClaudeProfile(path: "/Users/test/.claude-A", colorHex: "#ff0000", enabled: true, home: home),
        ]
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        #expect(back.claudeProfiles == settings.claudeProfiles)
    }

    // MARK: - Location guard

    @Test func homeAndAboveAreNotSafe() {
        #expect(!ClaudeProfile.isSafeLocation("/Users/test", home: home))
        #expect(!ClaudeProfile.isSafeLocation("~", home: home))
        #expect(!ClaudeProfile.isSafeLocation("/Users/test/", home: home))
        #expect(!ClaudeProfile.isSafeLocation("/Users", home: home))
        #expect(!ClaudeProfile.isSafeLocation("/", home: home))
        #expect(!ClaudeProfile.isSafeLocation("/Users/test/sub/..", home: home))
    }

    @Test func foldersBelowHomeAndSiblingsAreSafe() {
        #expect(ClaudeProfile.isSafeLocation("/Users/test/.claude-A", home: home))
        #expect(ClaudeProfile.isSafeLocation("/Users/test2/.claude", home: home))
        #expect(ClaudeProfile.isSafeLocation("/Volumes/Work/.claude-W", home: home))
    }

    @Test func symlinkToHomeIsNotSafe() throws {
        let h = try makeHome([])
        let link = h + "/.claude-link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: h)
        let profile = ClaudeProfile(path: link, enabled: true, home: h)
        #expect(!profile.isSafeLocation(home: h))
    }

    @Test func mergedDropsStoredAndFoundUnsafePaths() {
        let stored = [
            ClaudeProfile(path: "/Users/test", enabled: true, integration: true, home: home),
            ClaudeProfile(path: "/Users", enabled: true, home: home),
            ClaudeProfile(path: "/Users/test/.claude-A", enabled: true, home: home),
        ]
        let result = ClaudeProfile.merged(stored: stored, found: ["/Users/test", "/"], home: home)
        #expect(result.map(\.path) == ["/Users/test/.claude", "/Users/test/.claude-A"])
    }

    @Test func profileLauncherIdRoundTrips() throws {
        let profile = ClaudeProfile(path: "/Users/test/.claude-A", launcherId: "codemie", home: home)
        let back = try JSONDecoder().decode(ClaudeProfile.self, from: JSONEncoder().encode(profile))
        #expect(back.launcherId == "codemie")
    }

    @Test func oldProfileDecodesWithNilLauncherId() throws {
        let json = #"{"path": "/Users/test/.claude-A", "enabled": true}"#
        let profile = try JSONDecoder().decode(ClaudeProfile.self, from: Data(json.utf8))
        #expect(profile.launcherId == nil)
        let blank = #"{"path": "/Users/test/.claude-A", "launcherId": "  "}"#
        #expect(try JSONDecoder().decode(ClaudeProfile.self, from: Data(blank.utf8)).launcherId == nil)
        let bad = #"{"path": "/Users/test/.claude-A", "launcherId": 5}"#
        #expect(try JSONDecoder().decode(ClaudeProfile.self, from: Data(bad.utf8)).launcherId == nil)
    }
}
