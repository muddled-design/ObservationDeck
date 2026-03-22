import Foundation

@Observable
final class SessionStore {
    var sessions: [ClaudeSession] = []
    var lastRefreshed: Date?

    private var timer: Timer?
    private var sessionMap: [String: ClaudeSession] = [:]
    private var fileWatcher: FileWatcher?
    private var hookWatcher: HookSignalWatcher?

    /// How long a hook signal stays authoritative before falling back to heuristics.
    /// Hook signals are precise, so we trust them for a generous window.
    private static let hookSignalTTL: TimeInterval = 30

    /// Fallback: how long after the last file write before transitioning to "Needs Input"
    /// (only used when no recent hook signal exists).
    private static let idleThreshold: TimeInterval = 3

    func startPolling(interval: TimeInterval = 1.0) {
        guard timer == nil else { return }

        fileWatcher = FileWatcher { [weak self] sessionId in
            DispatchQueue.main.async {
                self?.onFileWrite(sessionId: sessionId)
            }
        }

        hookWatcher = HookSignalWatcher { [weak self] signal in
            DispatchQueue.main.async {
                self?.onHookSignal(signal)
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
        hookWatcher = nil
    }

    /// Called instantly when a JSONL file is written to
    private func onFileWrite(sessionId: String) {
        guard let session = sessionMap[sessionId] else { return }
        session.lastWriteEvent = Date()
        if session.status != .running {
            session.status = .running
        }
    }

    /// Called instantly when Claude Code fires a hook event
    private func onHookSignal(_ signal: HookSignalWatcher.Signal) {
        guard let session = sessionMap[signal.sessionId] else { return }
        session.hookSignalStatus = signal.status
        session.hookSignalTimestamp = signal.timestamp

        switch signal.status {
        case "running":
            session.status = .running
        case "stopped", "needs_input":
            session.status = .needsInput
        default:
            break
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
                session.hookSignalStatus = nil
            } else {
                activeSessionIds.insert(file.sessionId)

                // Priority 1: Recent hook signal from Claude Code itself (most authoritative)
                let hookAge: TimeInterval
                if let hookTS = session.hookSignalTimestamp {
                    hookAge = Date().timeIntervalSince(hookTS)
                } else {
                    hookAge = .infinity
                }

                if hookAge < Self.hookSignalTTL, let hookStatus = session.hookSignalStatus {
                    // Trust the hook signal
                    switch hookStatus {
                    case "running":
                        session.status = .running
                    case "stopped", "needs_input":
                        session.status = .needsInput
                    default:
                        break
                    }
                } else {
                    // Priority 2: File activity + CPU heuristics (fallback)
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
                    let currentCPU = ProcessMonitor.totalCPUTime(pid: file.pid)
                    let cpuActive = session.lastCPUTime.map { currentCPU > $0 } ?? false
                    session.lastCPUTime = currentCPU

                    if staleness < Self.idleThreshold || cpuActive {
                        session.status = .running
                    } else {
                        session.status = .needsInput
                    }
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
        hookWatcher?.pruneExcept(activeIds: activeSessionIds)

        sessionMap = updated
        // Stable order: sort by start time only (newest first). Never reorder based on status.
        sessions = Array(updated.values).sorted { a, b in
            a.startedAt > b.startedAt
        }
        lastRefreshed = Date()
    }
}
