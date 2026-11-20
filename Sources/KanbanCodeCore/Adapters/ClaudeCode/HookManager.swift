import Foundation

/// Manages hook installation for coding assistants that expose settings hooks.
///
/// Claude Code and Gemini CLI use the same hook configuration format:
/// `settings.json` → `hooks` → `{ EventName: [{ matcher, hooks: [{ type, command }] }] }`
///
/// The same hook script (`~/.kanban-code/hook.sh`) works for both because both pass
/// `session_id`, `hook_event_name`, and `transcript_path` via stdin JSON.
/// The orchestrator normalizes Gemini-specific event names (e.g. `AfterAgent` → `Stop`).
public enum HookManager {

    /// Hook events needed per assistant. Event names differ but serve the same purpose.
    public static func requiredHooks(for assistant: CodingAssistant) -> [String] {
        switch assistant {
        case .claude:
            [
                "Stop", "Notification", "SessionStart", "SessionEnd", "UserPromptSubmit",
                "SubagentStart", "SubagentStop",
            ]
        case .gemini:
            ["AfterAgent", "Notification", "SessionStart", "SessionEnd", "BeforeAgent"]
        case .codex:
            []
        }
    }

    /// Claude Code's required hooks (backward compat).
    static let requiredHooks = requiredHooks(for: .claude)

    /// Normalize Gemini event names to the canonical names the orchestrator understands.
    public static func normalizeEventName(_ name: String) -> String {
        switch name {
        case "AfterAgent": "Stop"
        case "BeforeAgent": "UserPromptSubmit"
        default: name
        }
    }

    // MARK: - Check

    /// Check if hooks are already installed for the given assistant.
    public static func isInstalled(for assistant: CodingAssistant, settingsPath: String? = nil) -> Bool {
        guard assistant.supportsHooks else { return false }

        let path = settingsPath ?? defaultSettingsPath(for: assistant)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }

        return requiredHooks(for: assistant).allSatisfy { eventName in
            guard let groups = hooks[eventName] as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard let hookEntries = group["hooks"] as? [[String: Any]] else { return false }
                return hookEntries.contains { entry in
                    (entry["command"] as? String)?.contains(".kanban-code/hook.sh") == true
                }
            }
        }
    }

    /// Backward-compatible: check Claude hooks only.
    public static func isInstalled(claudeSettingsPath: String? = nil) -> Bool {
        isInstalled(for: .claude, settingsPath: claudeSettingsPath)
    }

    /// Rewrite the deployed hook script when a release changed its content.
    ///
    /// Only for a script that is already on disk: a machine that never
    /// installed hooks is left to the Settings flow.
    @discardableResult
    public static func refreshHookScript(at path: String? = nil) -> Bool {
        let scriptPath = path ?? defaultHookScriptPath()
        guard let current = try? String(contentsOfFile: scriptPath, encoding: .utf8),
            current != hookScriptContent
        else { return false }
        do {
            try deployHookScript(to: scriptPath)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Install

    /// Install hooks for the given assistant.
    public static func install(
        for assistant: CodingAssistant,
        settingsPath: String? = nil,
        hookScriptPath: String? = nil,
        recordsOptIn: Bool = true
    ) throws {
        guard assistant.supportsHooks else {
            throw HookManagerError.unsupportedAssistant(assistant.displayName)
        }

        let resolvedSettingsPath = settingsPath ?? defaultSettingsPath(for: assistant)
        let scriptPath = hookScriptPath ?? defaultHookScriptPath()

        // Deploy the hook script to disk
        try deployHookScript(to: scriptPath)

        // Read existing settings; a file that does not parse is not replaced.
        var root: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: resolvedSettingsPath) {
            guard let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw HookManagerError.unreadableSettings(resolvedSettingsPath)
            }
            root = existing
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let hookEntry: [String: Any] = [
            "type": "command",
            "command": scriptPath,
        ]

        for eventName in requiredHooks(for: assistant) {
            var groups = hooks[eventName] as? [[String: Any]] ?? []

            // Check if .kanban-code/hook.sh already exists in any group
            let alreadyInstalled = groups.contains { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return false }
                return entries.contains { ($0["command"] as? String)?.contains(".kanban-code/hook.sh") == true }
            }

            if !alreadyInstalled {
                if groups.isEmpty {
                    groups.append(["matcher": "", "hooks": [hookEntry]])
                } else {
                    var firstGroup = groups[0]
                    var entries = firstGroup["hooks"] as? [[String: Any]] ?? []
                    entries.append(hookEntry)
                    firstGroup["hooks"] = entries
                    groups[0] = firstGroup
                }
            }

            hooks[eventName] = groups
        }

        root["hooks"] = hooks

        // Write back
        let fileManager = FileManager.default
        let dir = (resolvedSettingsPath as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try HookRestorer.writeSettings(data, to: resolvedSettingsPath)

        // Also install statusline for context tracking (Claude only)
        if assistant == .claude {
            // The statusline script lives beside the hook script.
            let statusLineScript = ((scriptPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("statusline.sh")
            try? installStatusLine(for: assistant, settingsPath: resolvedSettingsPath, scriptPath: statusLineScript)
        }
        // A profile other than `~/.claude` passes `recordsOptIn: false`: its
        // own switch is its opt-in, and recording one here would make
        // `HookRestorer` fill `~/.claude` too.
        if recordsOptIn {
            HookRestorer.setOptedIn(true, for: assistant, kanbanHome: (scriptPath as NSString).deletingLastPathComponent)
        }
    }

    /// Backward-compatible: install Claude hooks only.
    public static func install(
        claudeSettingsPath: String? = nil,
        hookScriptPath: String? = nil
    ) throws {
        try install(for: .claude, settingsPath: claudeSettingsPath, hookScriptPath: hookScriptPath)
    }

    // MARK: - Uninstall

    /// Remove Kanban hooks from the given assistant's settings, and stop
    /// `HookRestorer` from putting them back. The choice is recorded in
    /// `kanbanHome`, by default `~/.kanban-code` when the default settings
    /// file is the one changed.
    public static func uninstall(
        for assistant: CodingAssistant,
        settingsPath: String? = nil,
        kanbanHome: String? = nil
    ) throws {
        guard assistant.supportsHooks else { return }

        if let home = kanbanHome ?? (settingsPath == nil ? HookRestorer.defaultKanbanHome : nil) {
            HookRestorer.setOptedIn(false, for: assistant, kanbanHome: home)
        }
        let resolvedSettingsPath = settingsPath ?? defaultSettingsPath(for: assistant)

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolvedSettingsPath)),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = root["hooks"] as? [String: Any] else {
            return
        }

        for eventName in requiredHooks(for: assistant) {
            if var groups = hooks[eventName] as? [[String: Any]] {
                for i in groups.indices {
                    if var entries = groups[i]["hooks"] as? [[String: Any]] {
                        entries.removeAll { ($0["command"] as? String)?.contains(".kanban-code/hook.sh") == true }
                        groups[i]["hooks"] = entries
                    }
                }
                groups.removeAll { group in
                    guard let entries = group["hooks"] as? [[String: Any]] else { return true }
                    return entries.isEmpty
                }
                if groups.isEmpty {
                    hooks.removeValue(forKey: eventName)
                } else {
                    hooks[eventName] = groups
                }
            }
        }

        root["hooks"] = hooks

        let newData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try HookRestorer.writeSettings(newData, to: resolvedSettingsPath)
    }

    /// Removes the entries of `event` whose command contains `marker`, the
    /// groups left empty and an event left empty. Other hooks stay. A missing
    /// or unparseable file is not touched.
    static func removeHookEntries(marker: String, event: String, settingsPath: String) throws {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var hooks = root["hooks"] as? [String: Any],
              var groups = hooks[event] as? [[String: Any]] else { return }
        var changed = false
        for i in groups.indices {
            guard var entries = groups[i]["hooks"] as? [[String: Any]] else { continue }
            let count = entries.count
            entries.removeAll { ($0["command"] as? String)?.contains(marker) == true }
            if entries.count != count { groups[i]["hooks"] = entries; changed = true }
        }
        guard changed else { return }
        groups.removeAll { ($0["hooks"] as? [[String: Any]])?.isEmpty == true }
        if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        root["hooks"] = hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try HookRestorer.writeSettings(out, to: settingsPath)
    }

    /// Backward-compatible: uninstall Claude hooks only.
    public static func uninstall(claudeSettingsPath: String? = nil) throws {
        try uninstall(for: .claude, settingsPath: claudeSettingsPath)
    }

    // MARK: - Private

    static func deployHookScript(to path: String) throws {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        try hookScriptContent.write(toFile: path, atomically: true, encoding: .utf8)

        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: path
        )
    }

    private static let hookScriptContent = """
    #!/usr/bin/env bash
    # Kanban hook handler for coding assistants (Claude Code, Gemini CLI).
    # Receives JSON on stdin from hooks, appends a timestamped
    # event line to ~/.kanban-code/hook-events.jsonl.

    set -euo pipefail

    # A side chat (/btw, /catchup) forks a session to answer a question and
    # writes nothing: it is not a session of the board.
    if [ -n "${KANBAN_SIDE_CHAT:-}" ]; then cat > /dev/null; exit 0; fi

    EVENTS_DIR="${HOME}/.kanban-code"
    EVENTS_FILE="${EVENTS_DIR}/hook-events.jsonl"

    # Ensure directory exists
    mkdir -p "$EVENTS_DIR"

    # Read the JSON payload from stdin
    input=$(cat)

    # Extract fields using lightweight parsing (no jq dependency)
    session_id=$(echo "$input" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    hook_event=$(echo "$input" | grep -o '"hook_event_name":"[^"]*"' | head -1 | cut -d'"' -f4)
    transcript=$(echo "$input" | grep -o '"transcript_path":"[^"]*"' | head -1 | cut -d'"' -f4)

    # Fallback: try sessionId (different hook formats)
    if [ -z "$session_id" ]; then
        session_id=$(echo "$input" | grep -o '"sessionId":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi

    # Skip if we couldn't extract a session ID
    [ -z "$session_id" ] && exit 0

    # Get current timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # SessionStart carries a source (startup, resume, clear, compact) that
    # tells a real fresh start apart from a compaction of a live session.
    # Gated on the event name: other payloads can carry a "source" key
    # inside user text or tool input, and that must not leak in here.
    extra=""
    if [ "$hook_event" = "SessionStart" ]; then
        start_source=$(echo "$input" | grep -o '"source":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        if [ -n "$start_source" ]; then
            extra=",\\"source\\":\\"$start_source\\""
        fi
    fi
    # A Notification carries its type (permission_prompt, idle_prompt, ...)
    # and text; the whole payload goes along, base64 so quotes survive.
    if [ "$hook_event" = "Notification" ]; then
        payload_b64=$(printf '%s' "$input" | base64 | tr -d '\\n')
        extra="$extra,\\"payloadB64\\":\\"$payload_b64\\""
    fi

    # Append event line
    printf '{"sessionId":"%s","event":"%s","timestamp":"%s","transcriptPath":"%s"%s}\\n' \\
        "$session_id" "$hook_event" "$timestamp" "$transcript" "$extra" >> "$EVENTS_FILE"
    """

    // MARK: - Statusline

    /// Check if the statusline script is installed for the given assistant.
    public static func isStatusLineInstalled(for assistant: CodingAssistant = .claude, settingsPath: String? = nil) -> Bool {
        guard assistant == .claude else { return false }
        let path = settingsPath ?? defaultSettingsPath(for: assistant)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = root["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return false
        }
        return command.contains(".kanban-code/statusline.sh")
    }

    /// Marker that tells Kanban's statusline command from anyone else's.
    static let statusLineMarker = ".kanban-code/statusline.sh"
    private static let chainFlag = " --chain '"

    /// Install the statusline script for context tracking.
    ///
    /// - No `statusLine`: Kanban's own is installed.
    /// - Kanban's already there: nothing changes.
    /// - Someone else's with a string `command`: it is wrapped, not replaced.
    ///   The command becomes `<script> --chain '<original>'`; `type`,
    ///   `refreshInterval`, `padding` and every other key stay. The script
    ///   records the context usage and passes the same stdin to the original.
    /// - Someone else's of another shape: left as it is.
    ///
    /// A `settings.json` that does not parse is never replaced.
    public static func installStatusLine(
        for assistant: CodingAssistant = .claude,
        settingsPath: String? = nil,
        scriptPath: String? = nil
    ) throws {
        guard assistant == .claude else { return }
        let resolvedSettingsPath = settingsPath ?? defaultSettingsPath(for: assistant)
        let resolvedScriptPath = scriptPath ?? defaultStatusLineScriptPath()

        var root = try readSettingsRoot(resolvedSettingsPath)

        if var existing = root["statusLine"] {
            // Kanban's own, or a foreign one: only a command string can be wrapped.
            guard var statusLine = existing as? [String: Any],
                  let command = statusLine["command"] as? String else { return }
            if command.contains(statusLineMarker) { return }
            try deployStatusLineScript(to: resolvedScriptPath)
            statusLine["command"] = "\(resolvedScriptPath)\(chainFlag)\(shellQuoteBody(command))'"
            existing = statusLine
            root["statusLine"] = existing
        } else {
            try deployStatusLineScript(to: resolvedScriptPath)
            root["statusLine"] = [
                "type": "command",
                "command": resolvedScriptPath
            ] as [String: Any]
        }

        try writeSettingsRoot(root, to: resolvedSettingsPath)
    }

    /// Takes Kanban's statusline out again. A chained command goes back to the
    /// exact original, a plain Kanban `statusLine` is removed, anything else
    /// stays. A `settings.json` that does not parse is not touched.
    public static func uninstallStatusLine(
        for assistant: CodingAssistant = .claude,
        settingsPath: String? = nil
    ) throws {
        guard assistant == .claude else { return }
        let resolvedSettingsPath = settingsPath ?? defaultSettingsPath(for: assistant)
        guard FileManager.default.fileExists(atPath: resolvedSettingsPath) else { return }
        var root = try readSettingsRoot(resolvedSettingsPath)
        guard var statusLine = root["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String,
              command.contains(statusLineMarker) else { return }

        if let original = chainedOriginal(of: command) {
            statusLine["command"] = original
            root["statusLine"] = statusLine
        } else {
            root.removeValue(forKey: "statusLine")
        }
        try writeSettingsRoot(root, to: resolvedSettingsPath)
    }

    /// The command a chained statusline wraps, or nil for a plain Kanban one.
    static func chainedOriginal(of command: String) -> String? {
        guard let marker = command.range(of: statusLineMarker),
              let flag = command.range(of: chainFlag, range: marker.upperBound..<command.endIndex),
              flag.lowerBound == marker.upperBound,
              command.hasSuffix("'") else { return nil }
        let body = command[flag.upperBound..<command.index(before: command.endIndex)]
        return body.replacingOccurrences(of: "'\\''", with: "'")
    }

    /// Escapes `'` for use inside a single-quoted shell word.
    private static func shellQuoteBody(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "'\\''")
    }

    /// The settings object, `[:]` for a missing file. Throws for a file that
    /// is not a JSON object so that it is never overwritten.
    private static func readSettingsRoot(_ path: String) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw HookManagerError.unreadableSettings(path)
        }
        return root
    }

    private static func writeSettingsRoot(_ root: [String: Any], to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try HookRestorer.writeSettings(data, to: path)
    }

    // MARK: - Paths

    /// Settings file path per assistant.
    public static func defaultSettingsPath(for assistant: CodingAssistant) -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent("\(assistant.configDirName)/settings.json")
    }

    private static func defaultSettingsPath() -> String {
        defaultSettingsPath(for: .claude)
    }

    private static func defaultHookScriptPath() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".kanban-code/hook.sh")
    }

    private static func defaultStatusLineScriptPath() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".kanban-code/statusline.sh")
    }

    static func deployStatusLineScript(to path: String) throws {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        try statusLineScriptContent.write(toFile: path, atomically: true, encoding: .utf8)

        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: path
        )
    }

    private static let statusLineScriptContent = """
    #!/usr/bin/env bash
    # Kanban Code statusline — captures context/token usage per session.
    # Claude Code sends JSON via stdin after each assistant response.
    # We write a summary to ~/.kanban-code/context/<session_id>.json.
    #
    # With `--chain '<command>'` the statusline the user had before is kept:
    # the same stdin goes to that command, its output is printed and its exit
    # status is returned. Writing the context file never stops the chain.
    # Without `--chain` nothing is printed.

    CHAIN=""
    if [ "${1:-}" = "--chain" ]; then
        CHAIN="${2:-}"
    fi

    # Keep stdin byte for byte, trailing newlines included.
    input=$(cat; printf x)
    input=${input%x}

    write_context() {
        CONTEXT_DIR="${HOME}/.kanban-code/context"
        mkdir -p "$CONTEXT_DIR" || return 0

        session_id=$(printf '%s' "$input" | grep -oE '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
        [ -z "$session_id" ] && return 0

        used_pct=$(printf '%s' "$input" | grep -oE '"used_percentage":[0-9.]+' | head -1 | cut -d: -f2)
        ctx_size=$(printf '%s' "$input" | grep -oE '"context_window_size":[0-9]+' | head -1 | cut -d: -f2)
        input_tokens=$(printf '%s' "$input" | grep -oE '"total_input_tokens":[0-9]+' | head -1 | cut -d: -f2)
        output_tokens=$(printf '%s' "$input" | grep -oE '"total_output_tokens":[0-9]+' | head -1 | cut -d: -f2)
        cost=$(printf '%s' "$input" | grep -oE '"total_cost_usd":[0-9.]+' | head -1 | cut -d: -f2)
        model=$(printf '%s' "$input" | grep -oE '"display_name":"[^"]*"' | head -1 | cut -d'"' -f4)

        # Atomic via temp + mv
        tmp_file="${CONTEXT_DIR}/.${session_id}.tmp"
        out_file="${CONTEXT_DIR}/${session_id}.json"
        printf '{"usedPercentage":%s,"contextWindowSize":%s,"totalInputTokens":%s,"totalOutputTokens":%s,"totalCostUsd":%s,"model":"%s"}' \\
            "${used_pct:-0}" "${ctx_size:-0}" "${input_tokens:-0}" "${output_tokens:-0}" "${cost:-0}" "${model:-}" > "$tmp_file" \\
            && mv -f "$tmp_file" "$out_file"
    }

    ( write_context ) >/dev/null 2>&1 || true

    if [ -n "$CHAIN" ]; then
        printf '%s' "$input" | bash -c "$CHAIN"
        exit $?
    fi

    # Empty output — data is consumed by Kanban Code, not displayed in terminal
    printf ''
    """
}

public enum HookManagerError: LocalizedError {
    case unsupportedAssistant(String)
    case unreadableSettings(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedAssistant(let name):
            "\(name) does not support Kanban hook installation"
        case .unreadableSettings(let path):
            "\(path) is not a JSON object, left as it is"
        }
    }
}
