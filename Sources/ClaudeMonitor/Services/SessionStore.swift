import Foundation

@Observable
final class SessionStore {
    var sessions: [ClaudeSession] = []
    var lastRefreshed: Date?

    private var timer: Timer?
    private var sessionMap: [String: ClaudeSession] = [:]
    private var fileWatcher: FileWatcher?

    /// How long after the last write event before transitioning to "Needs Input".
    /// FileWatcher provides real-time events, so this only needs to cover
    /// brief gaps between tool calls/streaming chunks — not full API thinking time.
    private static let idleThreshold: TimeInterval = 3

    func startPolling(interval: TimeInterval = 1.0) {
        guard timer == nil else { return }

        fileWatcher = FileWatcher { [weak self] sessionId in
            DispatchQueue.main.async {
                self?.onFileWrite(sessionId: sessionId)
            }
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        fileWatcher = nil
    }

    /// Called instantly when a JSONL file is written to
    private func onFileWrite(sessionId: String) {
        guard let session = sessionMap[sessionId] else { return }
        session.lastWriteEvent = Date()
        if session.status != .running {
            session.status = .running
        }
    }

    func refresh() {
        let files = SessionScanner.scanSessions()
        var updated: [String: ClaudeSession] = [:]
        var activeSessionIds: Set<String> = []

        for file in files {
            let session: ClaudeSession
            if let existing = sessionMap[file.sessionId] {
                session = existing
            } else {
                session = ClaudeSession(from: file)
            }

            // Update session name from history.jsonl (picks up /rename commands)
            session.title = SessionScanner.sessionName(for: file.sessionId)

            let alive = ProcessMonitor.isClaudeAlive(pid: file.pid)

            // Check activity across main JSONL + all subagent JSONLs
            let modDate = SessionScanner.latestActivityDate(
                cwd: file.cwd,
                sessionId: file.sessionId
            )
            session.lastJSONLModification = modDate

            let children = alive ? ProcessMonitor.childProcesses(of: file.pid) : []
            session.childProcesses = children

            if !alive {
                session.status = .finished
                session.lastCPUTime = nil
            } else {
                activeSessionIds.insert(file.sessionId)

                // Use the most recent signal: either FileWatcher event or file mod date
                let lastActivity: Date? = [session.lastWriteEvent, modDate]
                    .compactMap { $0 }
                    .max()

                let staleness: TimeInterval
                if let last = lastActivity {
                    staleness = Date().timeIntervalSince(last)
                } else {
                    staleness = .infinity
                }

                // CPU time check: detect active processing even without JSONL writes
                // (e.g. during API calls / "thinking" periods)
                let currentCPU = ProcessMonitor.totalCPUTime(pid: file.pid)
                let cpuActive = session.lastCPUTime.map { currentCPU > $0 } ?? false
                session.lastCPUTime = currentCPU

                if staleness < Self.idleThreshold || cpuActive {
                    session.status = .running
                } else {
                    session.status = .needsInput
                }

                // Watch all JSONL files (main + subagents) for this session
                let allPaths = SessionScanner.allJsonlPaths(
                    cwd: file.cwd,
                    sessionId: file.sessionId
                )
                for path in allPaths {
                    fileWatcher?.watch(sessionId: file.sessionId, path: path)
                }
            }

            updated[file.sessionId] = session
        }

        fileWatcher?.pruneExcept(activeIds: activeSessionIds)

        sessionMap = updated
        // Stable order: sort by start time only (newest first). Never reorder based on status.
        sessions = Array(updated.values).sorted { a, b in
            a.startedAt > b.startedAt
        }
        lastRefreshed = Date()
    }
}
