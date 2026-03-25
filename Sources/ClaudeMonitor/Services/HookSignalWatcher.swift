import Foundation

/// Reads ~/.claude/monitor-status/ for signal files written by Claude Code hooks.
/// Each file is {sessionId}.json containing status, event, cwd, and timestamp.
final class HookSignalWatcher {
    struct Signal {
        let sessionId: String
        let status: String
        let event: String
        let notificationType: String
        let cwd: String
        let timestamp: Date
    }

    private let statusDir: String

    init() {
        self.statusDir = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent(".claude/monitor-status")
        try? FileManager.default.createDirectory(
            atPath: statusDir,
            withIntermediateDirectories: true
        )
    }

    /// Read the latest signal for a specific session ID.
    func latestSignal(for sessionId: String) -> Signal? {
        let path = (statusDir as NSString).appendingPathComponent("\(sessionId).json")
        return readSignal(at: path)
    }

    /// Find the most recent signal matching a given cwd.
    /// Used when the session file's ID doesn't match the hook's session ID
    /// (e.g. after /exit and resume, or session ID rotation).
    func latestSignal(forCwd cwd: String) -> Signal? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: statusDir) else { return nil }

        var best: Signal?
        for file in files where file.hasSuffix(".json") {
            let path = (statusDir as NSString).appendingPathComponent(file)
            guard let signal = readSignal(at: path),
                  signal.cwd == cwd else { continue }
            if best == nil || signal.timestamp > best!.timestamp {
                best = signal
            }
        }
        return best
    }

    /// Scan all signals — returns every signal file.
    func allSignals() -> [Signal] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: statusDir) else { return [] }
        return files.compactMap { file -> Signal? in
            guard file.hasSuffix(".json") else { return nil }
            let path = (statusDir as NSString).appendingPathComponent(file)
            return readSignal(at: path)
        }
    }

    private func readSignal(at path: String) -> Signal? {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = obj["session_id"] as? String,
              let status = obj["status"] as? String,
              let event = obj["event"] as? String,
              let ts = obj["timestamp"] as? TimeInterval else { return nil }
        let cwd = obj["cwd"] as? String ?? ""
        let notificationType = obj["notification_type"] as? String ?? ""
        return Signal(
            sessionId: sessionId,
            status: status,
            event: event,
            notificationType: notificationType,
            cwd: cwd,
            timestamp: Date(timeIntervalSince1970: ts)
        )
    }

    /// Remove signal files older than a threshold with no matching active session
    func pruneStale(activeCwds: Set<String>, maxAge: TimeInterval = 3600) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: statusDir) else { return }
        let now = Date()
        for file in files where file.hasSuffix(".json") {
            let path = (statusDir as NSString).appendingPathComponent(file)
            guard let signal = readSignal(at: path) else {
                try? fm.removeItem(atPath: path)
                continue
            }
            // Only prune if old AND not matching any active cwd
            if now.timeIntervalSince(signal.timestamp) > maxAge,
               !activeCwds.contains(signal.cwd) {
                try? fm.removeItem(atPath: path)
            }
        }
    }
}
