import AppKit

/// Switches focus to the terminal window/tab running the given Claude process.
func activateTerminal(for pid: Int32) {
    guard let appPid = ProcessMonitor.terminalAppPID(for: pid) else { return }
    let exePath = ProcessMonitor.executablePath(for: appPid)
    let isTerminalApp = exePath.contains("Terminal.app")
    let tty = ProcessMonitor.ttyName(for: pid)

    if isTerminalApp, let tty = tty {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with i from 1 to count of tabs of w
                    if tty of tab i of w contains "\(tty)" then
                        set selected tab of w to tab i of w
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
            activate
        end tell
        """
        var error: NSDictionary?
        var scriptSucceeded = false
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            scriptSucceeded = (error == nil)
        }
        // Fall back to plain activate if AppleScript failed (e.g. Automation permission denied)
        if !scriptSucceeded {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier == appPid
            }) {
                app.activate()
            }
        }
    } else {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier == appPid
        }) {
            app.activate()
        }
    }
}
