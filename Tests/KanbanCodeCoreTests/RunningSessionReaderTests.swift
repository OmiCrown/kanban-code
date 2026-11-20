import Foundation
import Testing

@testable import KanbanCodeCore

@Suite("Running Claude instances read from a profile's sessions folder", .serialized)
struct RunningSessionReaderTests {
    private struct Rig {
        let root: String
        let profile: ClaudeProfile
    }

    private func makeRig(enabled: Bool = true) throws -> Rig {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("running-sessions-\(UUID().uuidString)")
        let profile = ClaudeProfile(path: root + "/.claude-A", enabled: enabled, home: root)
        try FileManager.default.createDirectory(
            atPath: profile.path + "/sessions", withIntermediateDirectories: true)
        return Rig(root: root, profile: profile)
    }

    private func write(
        _ rig: Rig, pid: Int32, sessionId: String, kind: String = "interactive",
        procStart: String = "Tue Nov 10 11:16:40 2026", name: String? = "my work"
    ) throws {
        var object: [String: Any] = [
            "pid": Int(pid), "sessionId": sessionId, "cwd": "/work/app",
            "startedAt": 1794309403405, "procStart": procStart, "kind": kind,
        ]
        if let name { object["name"] = name }
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: URL(fileURLWithPath: rig.profile.path + "/sessions/\(pid).json"))
    }

    @Test("a live interactive instance is listed with what its file says")
    func listsLiveInteractive() throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        try write(rig, pid: 101, sessionId: "s-live")
        try write(rig, pid: 102, sessionId: "s-gone")

        let found = RunningSessionReader.read(profiles: [rig.profile]) { pid, _ in pid == 101 }

        #expect(found.count == 1)
        #expect(found.first?.sessionId == "s-live")
        #expect(found.first?.pid == 101)
        #expect(found.first?.cwd == "/work/app")
        #expect(found.first?.name == "my work")
        #expect(found.first?.profilePath == rig.profile.path)
        #expect(found.first?.startedAt == Date(timeIntervalSince1970: 1794309403.405))
    }

    @Test("a dead pid is not listed")
    func skipsDeadPid() throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        try write(rig, pid: 101, sessionId: "s1")
        #expect(RunningSessionReader.read(profiles: [rig.profile]) { _, _ in false }.isEmpty)
    }

    @Test("only interactive instances count")
    func skipsNonInteractive() throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        try write(rig, pid: 101, sessionId: "s1", kind: "sdk")
        #expect(RunningSessionReader.read(profiles: [rig.profile]) { _, _ in true }.isEmpty)
    }

    @Test("a disabled profile is not read")
    func skipsDisabledProfile() throws {
        let rig = try makeRig(enabled: false)
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        try write(rig, pid: 101, sessionId: "s1")
        #expect(RunningSessionReader.read(profiles: [rig.profile]) { _, _ in true }.isEmpty)
    }

    @Test("a file that cannot be parsed is skipped, the others are still listed")
    func ignoresBrokenFile() throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        try "not json".write(
            toFile: rig.profile.path + "/sessions/55.json", atomically: true, encoding: .utf8)
        try write(rig, pid: 101, sessionId: "s1")
        let found = RunningSessionReader.read(profiles: [rig.profile]) { _, _ in true }
        #expect(found.map(\.sessionId) == ["s1"])
    }

    @Test("the file's procStart reaches the liveness check")
    func passesProcStartToCheck() throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        try write(rig, pid: 101, sessionId: "s1", procStart: "Tue Nov 10 11:16:40 2026")
        nonisolated(unsafe) var seen: [(Int32, String?)] = []
        _ = RunningSessionReader.read(profiles: [rig.profile]) { pid, start in
            seen.append((pid, start))
            return true
        }
        #expect(seen.count == 1)
        #expect(seen.first?.0 == 101)
        #expect(seen.first?.1 == "Tue Nov 10 11:16:40 2026")
    }

    @Test("key files next to the json files are not read")
    func ignoresKeyFiles() throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        try write(rig, pid: 101, sessionId: "s1")
        try "{\"pid\":7,\"sessionId\":\"key\",\"cwd\":\"/x\",\"kind\":\"interactive\"}".write(
            toFile: rig.profile.path + "/sessions/7.abcdef0123.key", atomically: true, encoding: .utf8)
        let found = RunningSessionReader.read(profiles: [rig.profile]) { _, _ in true }
        #expect(found.map(\.sessionId) == ["s1"])
    }

    @Test("a process is alive only when the pid exists and its start time matches")
    func processIsAlive() {
        let me = getpid()
        #expect(RunningSessionReader.processIsAlive(pid: me, procStart: nil))
        #expect(!RunningSessionReader.processIsAlive(pid: me, procStart: "Mon Jan  1 00:00:00 1990"))
        #expect(!RunningSessionReader.processIsAlive(pid: 2_000_000_000, procStart: nil))
    }

    /// Claude writes `procStart` in English and UTC. A user whose shell is in
    /// another language and time zone must still see their processes alive.
    @Test("the start time is compared in English and UTC whatever the user's locale and zone")
    func processStartIgnoresLocaleAndZone() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "lstart=", "-p", String(getpid())]
        process.environment = ["LC_ALL": "C", "TZ": "UTC"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let expected = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!expected.isEmpty)

        let oldZone = getenv("TZ").map { String(cString: $0) }
        let oldLocale = getenv("LC_ALL").map { String(cString: $0) }
        setenv("TZ", "Pacific/Auckland", 1)
        setenv("LC_ALL", "uk_UA.UTF-8", 1)
        defer {
            if let oldZone { setenv("TZ", oldZone, 1) } else { unsetenv("TZ") }
            if let oldLocale { setenv("LC_ALL", oldLocale, 1) } else { unsetenv("LC_ALL") }
        }

        #expect(RunningSessionReader.processIsAlive(pid: getpid(), procStart: expected))
    }

    @Test("the ids of running sessions come back as a set")
    func runningSessionIds() throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(atPath: rig.root) }
        try write(rig, pid: getpid(), sessionId: "mine", procStart: "")
        let ids = RunningSessionReader.runningSessionIds(profiles: [rig.profile])
        #expect(ids == ["mine"])
    }
}
