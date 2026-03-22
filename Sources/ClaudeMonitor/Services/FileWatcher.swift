import Foundation

/// Watches files for write events using GCD dispatch sources.
/// Fires a callback immediately when a watched file is modified.
/// Supports multiple files per session (main JSONL + subagent JSONLs).
final class FileWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var pathToSession: [String: String] = [:]
    private let queue = DispatchQueue(label: "com.claudemonitor.filewatcher", qos: .utility)
    private let onChange: (String) -> Void

    /// onChange is called with the sessionId when any of its files is written to
    init(onChange: @escaping (String) -> Void) {
        self.onChange = onChange
    }

    /// Start watching a file for a given session. Safe to call multiple times for the same path.
    func watch(sessionId: String, path: String) {
        guard sources[path] == nil else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.onChange(sessionId)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources[path] = source
        pathToSession[path] = sessionId
    }

    /// Stop watching all files for sessions not in the given set
    func pruneExcept(activeIds: Set<String>) {
        let pathsToRemove = pathToSession.filter { !activeIds.contains($0.value) }.map(\.key)
        for path in pathsToRemove {
            if let source = sources.removeValue(forKey: path) {
                source.cancel()
            }
            pathToSession.removeValue(forKey: path)
        }
    }

    deinit {
        for (_, source) in sources {
            source.cancel()
        }
    }
}
