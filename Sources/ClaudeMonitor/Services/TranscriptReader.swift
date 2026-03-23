import Foundation

enum TranscriptReader {
    /// Read the last activity description from a JSONL transcript file.
    /// Reads only the tail of the file for efficiency.
    static func lastActivity(at path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }

        // Read last 32KB — enough to find the most recent tool_use
        let fileSize = fh.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 32768)
        fh.seek(toFileOffset: fileSize - readSize)
        let data = fh.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        // Walk lines in reverse to find the last assistant message with tool_use
        let lines = text.components(separatedBy: "\n").reversed()
        for line in lines {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = obj["type"] as? String,
                  type == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }

            // Find the last tool_use in this message's content
            for item in content.reversed() {
                guard let itemType = item["type"] as? String,
                      itemType == "tool_use",
                      let toolName = item["name"] as? String else { continue }

                let input = item["input"] as? [String: Any]
                return describeToolUse(tool: toolName, input: input)
            }

            // If assistant message has text content (not tool_use), use that
            for item in content.reversed() {
                guard let itemType = item["type"] as? String,
                      itemType == "text",
                      let text = item["text"] as? String,
                      !text.isEmpty else { continue }
                // Return first line, truncated
                let firstLine = text.components(separatedBy: "\n").first ?? text
                return String(firstLine.prefix(80))
            }
        }
        return nil
    }

    private static func describeToolUse(tool: String, input: [String: Any]?) -> String {
        guard let input = input else { return tool }

        switch tool {
        case "Bash":
            if let desc = input["description"] as? String, !desc.isEmpty {
                return desc
            }
            if let cmd = input["command"] as? String {
                return String(cmd.prefix(60))
            }
            return "Running command"

        case "Read":
            if let path = input["file_path"] as? String {
                return "Reading \(abbreviate(path))"
            }
            return "Reading file"

        case "Edit":
            if let path = input["file_path"] as? String {
                return "Editing \(abbreviate(path))"
            }
            return "Editing file"

        case "Write":
            if let path = input["file_path"] as? String {
                return "Writing \(abbreviate(path))"
            }
            return "Writing file"

        case "Grep":
            if let pattern = input["pattern"] as? String {
                return "Searching for \"\(String(pattern.prefix(40)))\""
            }
            return "Searching"

        case "Glob":
            if let pattern = input["pattern"] as? String {
                return "Finding \(pattern)"
            }
            return "Finding files"

        case "Agent":
            if let desc = input["description"] as? String, !desc.isEmpty {
                return desc
            }
            return "Running subagent"

        default:
            return tool
        }
    }

    private static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var p = path
        if p.hasPrefix(home) {
            p = "~" + p.dropFirst(home.count)
        }
        // Show just filename for short display
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
