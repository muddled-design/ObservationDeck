import Foundation

@Observable
final class SessionStore {
    var sessions: [ClaudeSession] = []
    var lastRefreshed: Date?

    private var timer: Timer?
    private var sessionMap: [String: ClaudeSession] = [:]
    private var jsonlIdCache: [String: String] = [:]
    private var fileWatcher: FileWatcher?
    private var hookWatcher: HookSignalWatcher?

    /// Fallback idle threshold — ONLY used for sessions with NO hook data at all.
    private static let idleThreshold: TimeInterval = 3

    /// How long after a Stop/Notification hook to ignore JSONL writes as "finalization".
    /// Writes within this window are the conversation log being flushed, not new work.
    /// Writes AFTER this window indicate the user sent a new message.
    private static let hookGracePeriod: TimeInterval = 2.0

    func startPolling(interval: TimeInterval = 1.0) {
        guard timer == nil else { return }

        fileWatcher = FileWatcher { [weak self] sessionId in
            DispatchQueue.main.async {
                self?.onFileWrite(sessionId: sessionId)
            }
        }

        hookWatcher = HookSignalWatcher()

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

    // MARK: - Instant callbacks

    /// Called instantly when a JSONL file is written to.
    private func onFileWrite(sessionId: String) {
        guard let session = sessionMap[sessionId] else { return }
        session.lastWriteEvent = Date()

        // Decide whether this write means "new work started":
        guard let hookStatus = session.hookSignalStatus else {
            // No hook data → heuristic mode, any write means running
            if session.status != .running { session.status = .running }
            return
        }

        if hookStatus == "running" {
            // Hook already says running → ensure UI matches
            if session.status != .running { session.status = .running }
            return
        }

        // Hook says idle/needs_input. Is this write finalization or new work?
        // If the hook fired recently (within grace period), this is finalization → ignore.
        // If the hook is old, this is a new user message → transition to running.
        if let hookTS = session.hookSignalTimestamp,
           Date().timeIntervalSince(hookTS) > Self.hookGracePeriod {
            if session.status != .running { session.status = .running }
        }
        // Otherwise: recent idle/needs_input hook + write = finalization → don't change status
    }

    // MARK: - Refresh (1s poll)

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

            let jsonlSessionId = resolveJsonlSessionId(for: file)

            // Read the latest hook signal for this session
            let hookSignal = hookWatcher?.latestSignal(for: jsonlSessionId)
                ?? hookWatcher?.latestSignal(for: file.sessionId)
                ?? hookWatcher?.latestSignal(forCwd: file.cwd)

            if let signal = hookSignal {
                session.hookSignalStatus = signal.status
                session.hookSignalTimestamp = signal.timestamp
            }

            session.title = SessionScanner.sessionName(for: file.sessionId)
                ?? SessionScanner.sessionName(for: jsonlSessionId)

            let alive = ProcessMonitor.isClaudeAlive(pid: file.pid)

            let modDate = SessionScanner.latestActivityDate(
                cwd: file.cwd,
                sessionId: jsonlSessionId
            )
            session.lastJSONLModification = modDate

            let children = alive ? ProcessMonitor.childProcesses(of: file.pid) : []
            session.childProcesses = children

            if !alive {
                // TC10: Process dead → Finished
                session.status = .finished
                session.lastCPUTime = nil
                session.hookSignalStatus = nil
            } else {
                activeSessionIds.insert(file.sessionId)

                let lastActivity: Date? = [session.lastWriteEvent, modDate]
                    .compactMap { $0 }
                    .max()

                if hookSignal != nil {
                    session.status = hookBasedStatus(
                        session: session,
                        lastActivity: lastActivity
                    )
                } else {
                    session.status = heuristicStatus(
                        session: session,
                        file: file,
                        lastActivity: lastActivity
                    )
                }

                let allPaths = SessionScanner.allJsonlPaths(
                    cwd: file.cwd,
                    sessionId: jsonlSessionId
                )
                for path in allPaths {
                    fileWatcher?.watch(sessionId: file.sessionId, path: path)
                }
            }

            updated[file.sessionId] = session
        }

        fileWatcher?.pruneExcept(activeIds: activeSessionIds)
        let activeCwds = Set(files.map { $0.cwd })
        hookWatcher?.pruneStale(activeCwds: activeCwds)

        sessionMap = updated
        sessions = Array(updated.values).sorted { a, b in
            a.startedAt > b.startedAt
        }
        lastRefreshed = Date()
    }

    // MARK: - Status determination

    /// Hook-based status. Key rules:
    /// - "running" from hook is STICKY — stays Running until Stop/Notification hook
    /// - "idle"/"needs_input" from hook wins UNLESS file activity happened well after
    ///   the hook (past the grace period), indicating new work started
    private func hookBasedStatus(
        session: ClaudeSession,
        lastActivity: Date?
    ) -> SessionStatus {
        let hookStatus = session.hookSignalStatus ?? "running"
        let hookTS = session.hookSignalTimestamp ?? .distantPast

        // Did meaningful file activity happen AFTER the hook's grace period?
        // This catches: user sends a new message after Claude went idle.
        // This ignores: finalization JSONL writes right after Stop hook.
        let newWorkAfterHook: Bool
        if let activity = lastActivity {
            newWorkAfterHook = activity.timeIntervalSince(hookTS) > Self.hookGracePeriod
        } else {
            newWorkAfterHook = false
        }

        switch hookStatus {
        case "idle":
            // TC5: Stop hook → Idle
            // TC1: But new work after grace period → Running
            return newWorkAfterHook ? .running : .idle

        case "needs_input":
            // TC6: Permission prompt → Needs Input
            // TC7: New work after grace period → Running
            return newWorkAfterHook ? .running : .needsInput

        default:
            // TC2, TC3, TC4, TC8, TC9: hook says "running" → STICKY Running.
            // No timeout, no heuristic override. Only Stop/Notification ends this.
            return .running
        }
    }

    /// Heuristic status for sessions with no hook data (pre-hooks or misconfigured).
    private func heuristicStatus(
        session: ClaudeSession,
        file: SessionFile,
        lastActivity: Date?
    ) -> SessionStatus {
        let staleness: TimeInterval
        if let last = lastActivity {
            staleness = Date().timeIntervalSince(last)
        } else {
            staleness = .infinity
        }

        let currentCPU = ProcessMonitor.totalCPUTime(pid: file.pid)
        let cpuDelta = session.lastCPUTime.map { currentCPU &- $0 } ?? 0
        let cpuActive = cpuDelta > 10_000_000
        session.lastCPUTime = currentCPU

        if staleness < Self.idleThreshold || cpuActive {
            return .running
        } else {
            return .idle
        }
    }

    // MARK: - Helpers

    private func resolveJsonlSessionId(for file: SessionFile) -> String {
        if let cached = jsonlIdCache[file.sessionId] {
            if SessionScanner.jsonlPath(cwd: file.cwd, sessionId: cached) != nil {
                return cached
            }
        }
        if SessionScanner.jsonlPath(cwd: file.cwd, sessionId: file.sessionId) != nil {
            jsonlIdCache[file.sessionId] = file.sessionId
            return file.sessionId
        }
        if let activeId = SessionScanner.activeJsonlSessionId(cwd: file.cwd) {
            jsonlIdCache[file.sessionId] = activeId
            return activeId
        }
        return file.sessionId
    }
}
