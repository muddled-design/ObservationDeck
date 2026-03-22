import Foundation
import CLibProc

enum ProcessMonitor {
    static func isAlive(pid: Int32) -> Bool {
        let result = kill(pid, 0)
        if result == 0 { return true }
        return errno == EPERM
    }

    /// Check if PID is alive AND is actually a Claude process (not a reused PID).
    /// proc_name returns the version string (e.g. "2.1.81"), so we check the
    /// executable path instead which contains "claude".
    static func isClaudeAlive(pid: Int32) -> Bool {
        guard isAlive(pid: pid) else { return false }
        let path = executablePath(for: pid).lowercased()
        if path.contains("claude") { return true }
        // Fallback: Claude's proc_name is a version string like "2.1.81"
        let name = processName(for: pid)
        let isVersionString = name.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
        return isVersionString
    }

    static func childPIDs(of pid: Int32) -> [Int32] {
        let bufferSize = proc_listchildpids(pid, nil, 0)
        guard bufferSize > 0 else { return [] }

        let count = Int(bufferSize) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: count)
        let actual = proc_listchildpids(pid, &pids, bufferSize)
        guard actual > 0 else { return [] }
        let actualCount = min(Int(actual) / MemoryLayout<Int32>.size, count)
        return Array(pids.prefix(actualCount)).filter { $0 != 0 }
    }

    /// Iterative BFS with cycle protection and a hard cap on total processes
    static func allDescendants(of pid: Int32, limit: Int = 500) -> [Int32] {
        var result: [Int32] = []
        var queue = childPIDs(of: pid)
        var visited: Set<Int32> = [pid]

        while !queue.isEmpty, result.count < limit {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            result.append(current)
            queue.append(contentsOf: childPIDs(of: current))
        }
        return result
    }

    static func processName(for pid: Int32) -> String {
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, UInt32(name.count))
        let result = String(cString: name)
        return result.isEmpty ? "unknown" : result
    }

    static func executablePath(for pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let ret = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard ret > 0 else { return "" }
        return String(cString: buffer)
    }

    /// Returns the total CPU time (user + system) in nanoseconds for a process and all descendants.
    /// Compare between polls to detect if the process is actively using CPU.
    static func totalCPUTime(pid: Int32) -> UInt64 {
        var total: UInt64 = cpuTimeForPid(pid)
        for child in allDescendants(of: pid) {
            total += cpuTimeForPid(child)
        }
        return total
    }

    private static func cpuTimeForPid(_ pid: Int32) -> UInt64 {
        var ti = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size)
        guard ret > 0 else { return 0 }
        return ti.pti_total_user + ti.pti_total_system
    }

    static func childProcesses(of pid: Int32) -> [ChildProcess] {
        allDescendants(of: pid).map { childPid in
            ChildProcess(pid: childPid, name: processName(for: childPid))
        }
    }
}
