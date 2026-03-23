import Foundation

/// Checks whether ClaudeMonitor hooks are installed in Claude Code settings,
/// and provides one-click installation.
@Observable
final class HookInstaller {
    enum State: Equatable {
        case checking
        case installed
        case notInstalled
        case justInstalled
        case failed(String)
    }

    private(set) var state: State = .checking

    private let hookCommand = "bash ~/.claude/monitor-hook.sh"
    private let settingsPath: String
    private let hookScriptDest: String

    /// The events that need the monitor hook registered.
    private let requiredEvents = [
        "Stop", "Notification", "PreToolUse", "PostToolUse",
        "SubagentStart", "SubagentStop"
    ]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.settingsPath = (home as NSString).appendingPathComponent(".claude/settings.json")
        self.hookScriptDest = (home as NSString).appendingPathComponent(".claude/monitor-hook.sh")
    }

    /// Check if hooks are already configured.
    func check() {
        state = .checking
        state = isInstalled() ? .installed : .notInstalled
    }

    /// Install the hook script and register it in settings.json.
    func install() {
        do {
            try installHookScript()
            try registerInSettings()
            state = .justInstalled
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Detection

    private func isInstalled() -> Bool {
        // Check if settings.json exists and contains our hook command
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath),
              let data = fm.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        // Verify the hook command is present in at least one event
        for event in requiredEvents {
            if !eventContainsMonitorHook(hooks: hooks, event: event) {
                return false
            }
        }
        return true
    }

    private func eventContainsMonitorHook(hooks: [String: Any], event: String) -> Bool {
        guard let rules = hooks[event] as? [[String: Any]] else { return false }
        for rule in rules {
            guard let hookArray = rule["hooks"] as? [[String: Any]] else { continue }
            for hook in hookArray {
                if let cmd = hook["command"] as? String, cmd == hookCommand {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Installation

    /// Copy the bundled hook script to ~/.claude/monitor-hook.sh
    private func installHookScript() throws {
        let fm = FileManager.default

        // The hook script is bundled as a resource in the app
        // First try the bundle, then fall back to the script embedded as a string
        let scriptContent = Self.embeddedHookScript

        let claudeDir = (fm.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent(".claude")
        try fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        try scriptContent.write(toFile: hookScriptDest, atomically: true, encoding: .utf8)

        // Make executable
        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookScriptDest
        )
    }

    /// Add the monitor hook to settings.json for all required events.
    private func registerInSettings() throws {
        let fm = FileManager.default
        var json: [String: Any]

        if fm.fileExists(atPath: settingsPath),
           let data = fm.contents(atPath: settingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        } else {
            json = [:]
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let monitorHookEntry: [String: Any] = [
            "type": "command",
            "command": hookCommand,
            "async": true
        ]

        for event in requiredEvents {
            var rules = hooks[event] as? [[String: Any]] ?? []

            // Check if already present
            var found = false
            for rule in rules {
                if let hookArray = rule["hooks"] as? [[String: Any]] {
                    for hook in hookArray {
                        if let cmd = hook["command"] as? String, cmd == hookCommand {
                            found = true
                            break
                        }
                    }
                }
                if found { break }
            }

            if !found {
                if rules.isEmpty {
                    // Create a new rule with our hook
                    rules.append(["hooks": [monitorHookEntry]])
                } else {
                    // Append our hook to the first rule's hooks array
                    var firstRule = rules[0]
                    var hookArray = firstRule["hooks"] as? [[String: Any]] ?? []
                    hookArray.append(monitorHookEntry)
                    firstRule["hooks"] = hookArray
                    rules[0] = firstRule
                }
                hooks[event] = rules
            }
        }

        json["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: settingsPath))
    }

    // MARK: - Embedded hook script

    /// The monitor-hook.sh content, embedded so the app is self-contained.
    private static let embeddedHookScript = """
    #!/bin/bash
    # Claude Code hook script for ClaudeMonitor
    # Reads hook event JSON from stdin and writes a status signal file.
    # Uses python3 to parse all fields in one call for efficiency.

    INPUT=$(cat)

    eval "$(echo "$INPUT" | /usr/bin/python3 -c "
    import sys, json, os
    d = json.load(sys.stdin)
    sid = d.get('session_id', '')
    event = d.get('hook_event_name', '')
    ntype = d.get('notification_type', '')
    cwd = d.get('cwd', '')
    # Extract session ID from transcript path (most reliable identifier)
    tp = d.get('transcript_path', '')
    # transcript_path looks like: ~/.claude/projects/{encoded-path}/{sessionId}.jsonl
    tsid = os.path.splitext(os.path.basename(tp))[0] if tp else sid
    print(f'SESSION_ID=\"{sid}\"')
    print(f'HOOK_EVENT=\"{event}\"')
    print(f'NOTIF_TYPE=\"{ntype}\"')
    print(f'CWD=\"{cwd}\"')
    print(f'TRANSCRIPT_SESSION_ID=\"{tsid}\"')
    " 2>/dev/null)"

    [ -z "$SESSION_ID" ] && exit 0

    STATUS_DIR="$HOME/.claude/monitor-status"
    mkdir -p "$STATUS_DIR"

    case "$HOOK_EVENT" in
      Stop)
        STATUS="idle"
        ;;
      Notification)
        case "$NOTIF_TYPE" in
          permission_prompt|elicitation_dialog)
            STATUS="needs_input"
            ;;
          *)
            STATUS="idle"
            ;;
        esac
        ;;
      PreToolUse|SubagentStart|PostToolUse|SubagentStop)
        STATUS="running"
        ;;
      *)
        STATUS="running"
        ;;
    esac

    # Write signal using BOTH the hook session ID and the transcript session ID
    # so the monitor can match by either
    echo "{\\"session_id\\":\\"$SESSION_ID\\",\\"transcript_session_id\\":\\"$TRANSCRIPT_SESSION_ID\\",\\"status\\":\\"$STATUS\\",\\"event\\":\\"$HOOK_EVENT\\",\\"notification_type\\":\\"$NOTIF_TYPE\\",\\"cwd\\":\\"$CWD\\",\\"timestamp\\":$(date +%s)}" > "$STATUS_DIR/$SESSION_ID.json"

    # Also write a symlink/copy by transcript session ID if different
    if [ "$TRANSCRIPT_SESSION_ID" != "$SESSION_ID" ] && [ -n "$TRANSCRIPT_SESSION_ID" ]; then
        cp "$STATUS_DIR/$SESSION_ID.json" "$STATUS_DIR/$TRANSCRIPT_SESSION_ID.json"
    fi
    """
}
