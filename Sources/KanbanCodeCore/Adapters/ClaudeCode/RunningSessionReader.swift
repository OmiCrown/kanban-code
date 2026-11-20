import Foundation

/// A Claude Code instance that runs now, as its `<profile>/sessions/<pid>.json` says.
public struct RunningSession: Equatable, Sendable, Identifiable {
    public var id: String { sessionId }
    public let pid: Int32
    public let sessionId: String
    public let cwd: String
    public let name: String?
    public let startedAt: Date?
    public let procStart: String?
    public let profilePath: String

    public init(
        pid: Int32, sessionId: String, cwd: String, name: String? = nil,
        startedAt: Date? = nil, procStart: String? = nil, profilePath: String
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.name = name
        self.startedAt = startedAt
        self.procStart = procStart
        self.profilePath = profilePath
    }
}

public enum RunningSessionReader {
    /// Live interactive instances of every enabled profile, newest start first.
    /// A file that cannot be read or parsed is skipped. `isAlive` gets the pid
    /// and the file's `procStart`.
    public static func read(
        profiles: [ClaudeProfile],
        isAlive: (Int32, String?) -> Bool = RunningSessionReader.processIsAlive
    ) -> [RunningSession] {
        let fm = FileManager.default
        var found: [RunningSession] = []
        for profile in profiles where profile.enabled && profile.exists {
            let dir = profile.path + "/sessions"
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() where isPidFile(name) {
                guard let data = fm.contents(atPath: dir + "/" + name),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pidValue = (object["pid"] as? NSNumber)?.int32Value,
                      let sessionId = object["sessionId"] as? String, !sessionId.isEmpty,
                      let cwd = object["cwd"] as? String,
                      (object["kind"] as? String) == "interactive"
                else { continue }
                let procStart = (object["procStart"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                guard isAlive(pidValue, procStart) else { continue }
                let claudeName = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let startedAt = (object["startedAt"] as? NSNumber)
                    .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
                found.append(RunningSession(
                    pid: pidValue, sessionId: sessionId, cwd: cwd, name: claudeName,
                    startedAt: startedAt, procStart: procStart, profilePath: profile.path))
            }
        }
        return found.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    /// The pid exists and, when `procStart` is known, the process started at
    /// that time (a reused pid belongs to another process).
    public static func processIsAlive(pid: Int32, procStart: String?) -> Bool {
        guard pid > 0 else { return false }
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        guard let procStart, !procStart.isEmpty else { return true }
        guard let actual = startText(ofPid: pid) else { return false }
        return collapse(actual) == collapse(procStart)
    }

    /// Session ids running now in any enabled profile.
    public static func runningSessionIds(profiles: [ClaudeProfile]) -> Set<String> {
        Set(read(profiles: profiles).map(\.sessionId))
    }

    // MARK: - Private

    /// `<digits>.json`: the `<pid>.<hash>.key` files next to it are not instances.
    private static func isPidFile(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let stem = name.dropLast(".json".count)
        return !stem.isEmpty && stem.allSatisfy(\.isNumber)
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `ps -o lstart=` for the pid, as Claude writes `procStart`.
    private static func startText(ofPid pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "lstart=", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
