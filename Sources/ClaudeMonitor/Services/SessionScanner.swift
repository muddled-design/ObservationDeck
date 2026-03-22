import Foundation

enum SessionScanner {
    private static let sessionsDir: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
            .path
    }()

    private static let projectsDir: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
            .path
    }()

    private static let historyPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/history.jsonl")
            .path
    }()

    private static var sessionNames: [String: String] = [:]
    private static var lastHistoryModDate: Date?

    static func scanSessions() -> [SessionFile] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
            return []
        }

        let decoder = JSONDecoder()
        return files.compactMap { filename -> SessionFile? in
            guard filename.hasSuffix(".json") else { return nil }
            let path = (sessionsDir as NSString).appendingPathComponent(filename)
            guard let data = fm.contents(atPath: path) else { return nil }
            return try? decoder.decode(SessionFile.self, from: data)
        }
    }

    static func jsonlPath(cwd: String, sessionId: String) -> String? {
        let encoded = PathEncoder.encode(cwd)
        let path = (projectsDir as NSString)
            .appendingPathComponent(encoded)
            .appending("/\(sessionId).jsonl")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    static func jsonlModificationDate(cwd: String, sessionId: String) -> Date? {
        guard let path = jsonlPath(cwd: cwd, sessionId: sessionId) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }

    /// Returns the most recent modification date across the main JSONL and all subagent JSONLs.
    /// This ensures subagent activity keeps the session marked as "Running".
    static func latestActivityDate(cwd: String, sessionId: String) -> Date? {
        let encoded = PathEncoder.encode(cwd)
        let fm = FileManager.default
        let sessionDir = (projectsDir as NSString)
            .appendingPathComponent(encoded)
            .appending("/\(sessionId)")
        let mainJsonl = (projectsDir as NSString)
            .appendingPathComponent(encoded)
            .appending("/\(sessionId).jsonl")

        var latest: Date? = nil

        // Check main JSONL
        if let attrs = try? fm.attributesOfItem(atPath: mainJsonl),
           let mod = attrs[.modificationDate] as? Date {
            latest = mod
        }

        // Check subagent JSONLs
        let subagentsDir = (sessionDir as NSString).appendingPathComponent("subagents")
        if let files = try? fm.contentsOfDirectory(atPath: subagentsDir) {
            for file in files where file.hasSuffix(".jsonl") {
                let path = (subagentsDir as NSString).appendingPathComponent(file)
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let mod = attrs[.modificationDate] as? Date {
                    if latest == nil || mod > latest! {
                        latest = mod
                    }
                }
            }
        }

        return latest
    }

    /// Returns paths to all JSONL files for a session (main + subagents) for file watching.
    static func allJsonlPaths(cwd: String, sessionId: String) -> [String] {
        let encoded = PathEncoder.encode(cwd)
        let fm = FileManager.default
        var paths: [String] = []

        let mainJsonl = (projectsDir as NSString)
            .appendingPathComponent(encoded)
            .appending("/\(sessionId).jsonl")
        if fm.fileExists(atPath: mainJsonl) {
            paths.append(mainJsonl)
        }

        let subagentsDir = (projectsDir as NSString)
            .appendingPathComponent(encoded)
            .appending("/\(sessionId)/subagents")
        if let files = try? fm.contentsOfDirectory(atPath: subagentsDir) {
            for file in files where file.hasSuffix(".jsonl") {
                paths.append((subagentsDir as NSString).appendingPathComponent(file))
            }
        }

        return paths
    }

    /// Get the explicit session name (from /rename command) if one exists.
    /// Reloads from history.jsonl if the file has been modified.
    static func sessionName(for sessionId: String) -> String? {
        reloadNamesIfNeeded()
        return sessionNames[sessionId]
    }

    private static func reloadNamesIfNeeded() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: historyPath)
        let modDate = attrs?[.modificationDate] as? Date
        guard modDate != lastHistoryModDate else { return }
        lastHistoryModDate = modDate
        sessionNames = loadSessionNames()
    }

    /// Scan history.jsonl for /rename commands and map sessionId → name.
    private static func loadSessionNames() -> [String: String] {
        guard let data = FileManager.default.contents(atPath: historyPath),
              let text = String(data: data, encoding: .utf8) else { return [:] }

        var names: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let display = obj["display"] as? String,
                  display.hasPrefix("/rename "),
                  let sessionId = obj["sessionId"] as? String else { continue }

            let name = String(display.dropFirst("/rename ".count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                names[sessionId] = name
            }
        }
        return names
    }
}
