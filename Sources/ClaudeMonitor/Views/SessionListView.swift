import SwiftUI
import AppKit

struct SessionListView: View {
    let store: SessionStore
    let hookInstaller: HookInstaller
    var isTranslucent: Bool = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isTranslucent ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HookSetupBanner(installer: hookInstaller)

                if store.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }

                statusBar
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(store.sessions) { session in
                    SessionDisclosureRow(session: session)
                }
            }
            .padding(.vertical, 6)
        }
        // Defeat the default white/gray scroll background so glass shows through
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            Text("No Claude Sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Start a Claude Code session in your terminal.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 0) {
            Group {
                if let lastRefreshed = store.lastRefreshed {
                    Text("Updated ")
                        .foregroundStyle(.quaternary)
                    + Text(lastRefreshed, style: .relative)
                        .foregroundStyle(.tertiary)
                    + Text(" ago")
                        .foregroundStyle(.quaternary)
                } else {
                    Text("Starting...")
                        .foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 10))

            Spacer()

            // Session count pill
            Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color(white: 0.5).opacity(0.10))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            // Hairline separator above the footer
            Rectangle()
                .fill(Color(white: 0.5).opacity(0.18))
                .frame(height: 0.5),
            alignment: .top
        )
        .background(Color(white: 0.5).opacity(0.12))
    }
}

// MARK: - Disclosure Row

/// Custom expandable row with a dedicated terminal-activate button.
/// Single-tap the row to expand/collapse; click the terminal icon to switch to that session.
struct SessionDisclosureRow: View {
    let session: ClaudeSession
    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
                    .frame(width: 20, height: 20)

                SessionRowView(session: session)

                // Terminal button — click to switch to this session's terminal tab
                Button {
                    activateTerminal(for: session.pid)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isHovering ? Color.secondary : Color.clear)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .help("Switch to terminal")
                .fixedSize()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }

            // Expandable child processes
            if isExpanded {
                VStack(spacing: 0) {
                    if session.childProcesses.isEmpty {
                        Text("No child processes")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                            .padding(.leading, 20)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(session.childProcesses) { child in
                            ChildProcessRow(process: child)
                        }
                    }
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .contextMenu {
            Button("Switch to Terminal") {
                activateTerminal(for: session.pid)
            }
        }
        // Subtle card background — just enough to lift from the glass
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.5).opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(white: 0.5).opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private func activateTerminal(for pid: Int32) {
        guard let appPid = ProcessMonitor.terminalAppPID(for: pid) else { return }
        let exePath = ProcessMonitor.executablePath(for: appPid)
        let isTerminalApp = exePath.contains("Terminal.app")
        let tty = ProcessMonitor.ttyName(for: pid)

        // Drop floating level so the terminal appears in front
        for w in NSApp.windows { w.level = .normal }

        if isTerminalApp, let tty = tty {
            // Use AppleScript to switch to the exact tab in Terminal.app
            let script = """
            tell application "Terminal"
                activate
                repeat with w in windows
                    repeat with i from 1 to count of tabs of w
                        if tty of tab i of w contains "\(tty)" then
                            set selected tab of w to tab i of w
                            set index of w to 1
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            """
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        } else {
            // Generic activation for iTerm, Warp, etc.
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier == appPid
            }) {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }

        // Restore floating after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for w in NSApp.windows { w.level = .floating }
        }
    }
}
