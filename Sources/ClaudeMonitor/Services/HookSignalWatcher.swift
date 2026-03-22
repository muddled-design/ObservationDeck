import Foundation

/// Watches ~/.claude/monitor-status/ for signal files written by Claude Code hooks.
/// Each file is {sessionId}.json with {"session_id", "status", "event", "timestamp"}.
/// This provides authoritative, instant status from Claude Code itself.
final class HookSignalWatcher {
    struct Signal {
        let sessionId: String
        let status: String
        let event: String
        let timestamp: Date
    }

    private let statusDir: String
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.claudemonitor.hooksignal", qos: .utility)
    private let onChange: (Signal) -> Void

    init(onChange: @escaping (Signal) -> Void) {
        self.statusDir = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent(".claude/monitor-status")
        self.onChange = onChange
        ensureDirectory()
        startWatching()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            atPath: statusDir,
            withIntermediateDirectories: true
        )
    }

    private func startWatching() {
        let fd = open(statusDir, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scanSignals()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.source = source

        // Initial scan
        queue.async { [weak self] in
            self?.scanSignals()
        }
    }

    private func scanSignals() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: statusDir) else { return }

        for file in files where file.hasSuffix(".json") {
            let path = (statusDir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = obj["session_id"] as? String,
                  let status = obj["status"] as? String,
                  let event = obj["event"] as? String,
                  let ts = obj["timestamp"] as? TimeInterval else { continue }

            let signal = Signal(
                sessionId: sessionId,
                status: status,
                event: event,
                timestamp: Date(timeIntervalSince1970: ts)
            )
            onChange(signal)
        }
    }

    /// Remove signal files for sessions that no longer exist
    func pruneExcept(activeIds: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: statusDir) else { return }
        for file in files where file.hasSuffix(".json") {
            let sessionId = String(file.dropLast(5)) // remove .json
            if !activeIds.contains(sessionId) {
                let path = (statusDir as NSString).appendingPathComponent(file)
                try? fm.removeItem(atPath: path)
            }
        }
    }

    deinit {
        source?.cancel()
    }
}
