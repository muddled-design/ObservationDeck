import Foundation

struct SessionFile: Codable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let startedAt: Int64
}

@Observable
final class ClaudeSession: Identifiable {
    let id: String
    let pid: Int32
    let cwd: String
    let startedAt: Date
    var status: SessionStatus
    var childProcesses: [ChildProcess]
    var lastJSONLModification: Date?
    /// Set by FileWatcher on every write event — more accurate than file mod date
    var lastWriteEvent: Date?
    /// First user message from JSONL, used as session title
    var title: String?
    /// CPU time (user+system nanoseconds) from last poll — used to detect active processing
    var lastCPUTime: UInt64?
    /// Last status signal from Claude Code hooks (authoritative source)
    var hookSignalStatus: String?
    var hookSignalTimestamp: Date?

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var duration: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    init(from file: SessionFile) {
        self.id = file.sessionId
        self.pid = file.pid
        self.cwd = file.cwd
        self.startedAt = Date(timeIntervalSince1970: Double(file.startedAt) / 1000.0)
        self.status = .finished
        self.childProcesses = []
        self.lastJSONLModification = nil
    }
}
