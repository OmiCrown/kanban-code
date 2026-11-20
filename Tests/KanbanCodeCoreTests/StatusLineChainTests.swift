import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("StatusLineChain")
struct StatusLineChainTests {
    private func makeDir() throws -> String {
        let dir = NSTemporaryDirectory() + "kanban-code-statusline-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeSettings(_ object: Any, to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func readSettings(_ path: String) throws -> [String: Any] {
        let data = try #require(FileManager.default.contents(atPath: path))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func statusLine(_ path: String) throws -> [String: Any]? {
        try readSettings(path)["statusLine"] as? [String: Any]
    }

    // MARK: Installer

    @Test func installsWhenAbsent() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        let script = dir + "/.kanban-code/statusline.sh"
        try writeSettings(["model": "opus"], to: settings)
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: script)
        let line = try #require(try statusLine(settings))
        #expect(line["command"] as? String == script)
        #expect(line["type"] as? String == "command")
        #expect(try readSettings(settings)["model"] as? String == "opus")
        #expect(FileManager.default.isExecutableFile(atPath: script))
    }

    @Test func wrapsForeign() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        let script = dir + "/.kanban-code/statusline.sh"
        try writeSettings(["statusLine": ["type": "command", "command": "usage-tracker --short", "refreshInterval": 60]], to: settings)
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: script)
        let line = try #require(try statusLine(settings))
        #expect(line["command"] as? String == "\(script) --chain 'usage-tracker --short'")
        #expect(line["refreshInterval"] as? Int == 60)
        #expect(line["type"] as? String == "command")
    }

    @Test func alreadyKanbanIsNoOp() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        let script = dir + "/.kanban-code/statusline.sh"
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: script)
        let before = try #require(FileManager.default.contents(atPath: settings))
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: script)
        #expect(FileManager.default.contents(atPath: settings) == before)
    }

    @Test func alreadyChainedIsNoOp() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        let script = dir + "/.kanban-code/statusline.sh"
        try writeSettings(["statusLine": ["type": "command", "command": "foreign"]], to: settings)
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: script)
        let before = try #require(FileManager.default.contents(atPath: settings))
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: script)
        #expect(FileManager.default.contents(atPath: settings) == before)
    }

    @Test func roundTripRestoresOriginal() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        let script = dir + "/.kanban-code/statusline.sh"
        let original: [String: Any] = [
            "type": "command",
            "command": #"echo "it's $HOME" | sed 's/a b/c d/' ; true"#,
            "refreshInterval": 30,
            "padding": 2,
        ]
        try writeSettings(["statusLine": original, "model": "opus"], to: settings)
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: script)
        try HookManager.uninstallStatusLine(settingsPath: settings)
        let restored = try #require(try statusLine(settings))
        #expect(NSDictionary(dictionary: restored).isEqual(to: original))
        #expect(try readSettings(settings)["model"] as? String == "opus")
    }

    @Test func uninstallRemovesPlainKanban() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: dir + "/.kanban-code/statusline.sh")
        try HookManager.uninstallStatusLine(settingsPath: settings)
        #expect(try statusLine(settings) == nil)
    }

    @Test func uninstallLeavesForeignAlone() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        try writeSettings(["statusLine": ["type": "command", "command": "foreign"]], to: settings)
        let before = try #require(FileManager.default.contents(atPath: settings))
        try HookManager.uninstallStatusLine(settingsPath: settings)
        #expect(FileManager.default.contents(atPath: settings) == before)
    }

    @Test func leavesUnknownShapeAlone() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        try writeSettings(["statusLine": ["type": "static", "text": "hi"]], to: settings)
        let before = try #require(FileManager.default.contents(atPath: settings))
        try HookManager.installStatusLine(settingsPath: settings, scriptPath: dir + "/.kanban-code/statusline.sh")
        #expect(FileManager.default.contents(atPath: settings) == before)
    }

    @Test(arguments: ["", "[1,2]", "not json"])
    func unparseableSettingsUntouched(content: String) throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let settings = dir + "/settings.json"
        try content.write(toFile: settings, atomically: true, encoding: .utf8)
        #expect(throws: HookManagerError.self) {
            try HookManager.installStatusLine(settingsPath: settings, scriptPath: dir + "/.kanban-code/statusline.sh")
        }
        #expect(try String(contentsOfFile: settings, encoding: .utf8) == content)
    }

    // MARK: Script

    private struct ScriptResult { var stdout: String; var status: Int32; var home: String }

    private func runScript(args: [String], stdin: String) throws -> ScriptResult {
        let home = try makeDir()
        let script = home + "/.kanban-code/statusline.sh"
        try HookManager.deployStatusLineScript(to: script)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: script)
        process.arguments = args
        process.environment = ["HOME": home, "PATH": "/usr/bin:/bin"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ScriptResult(stdout: String(decoding: out, as: UTF8.self), status: process.terminationStatus, home: home)
    }

    private let sample = #"{"session_id":"s1","context_window":{"used_percentage":5}}"#

    @Test func scriptPassesStdinToChain() throws {
        let r = try runScript(args: ["--chain", "cat"], stdin: sample + "\n")
        defer { try? FileManager.default.removeItem(atPath: r.home) }
        #expect(r.stdout == sample + "\n")
        #expect(r.status == 0)
        #expect(FileManager.default.fileExists(atPath: r.home + "/.kanban-code/context/s1.json"))
    }

    @Test func scriptChainFailureStillWritesContext() throws {
        let r = try runScript(args: ["--chain", "cat >/dev/null; exit 3"], stdin: sample)
        defer { try? FileManager.default.removeItem(atPath: r.home) }
        #expect(r.status == 3)
        #expect(FileManager.default.fileExists(atPath: r.home + "/.kanban-code/context/s1.json"))
    }

    @Test func scriptChainRunsWhenContextCannotBeWritten() throws {
        // A stdin without a session id writes nothing but the chain still runs.
        let r = try runScript(args: ["--chain", "cat"], stdin: #"{"x":1}"#)
        defer { try? FileManager.default.removeItem(atPath: r.home) }
        #expect(r.stdout == #"{"x":1}"#)
    }

    @Test func scriptWithoutChainPrintsNothing() throws {
        let r = try runScript(args: [], stdin: sample)
        defer { try? FileManager.default.removeItem(atPath: r.home) }
        #expect(r.stdout.isEmpty)
        #expect(r.status == 0)
        #expect(FileManager.default.fileExists(atPath: r.home + "/.kanban-code/context/s1.json"))
    }
}
