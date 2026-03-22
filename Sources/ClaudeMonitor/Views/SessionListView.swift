import SwiftUI
import AppKit

struct SessionListView: View {
    let store: SessionStore
    var isTranslucent: Bool = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isTranslucent ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial))
                .ignoresSafeArea()

            VStack(spacing: 0) {
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

/// Wraps the DisclosureGroup so its expand/collapse state is self-contained per session.
struct SessionDisclosureRow: View {
    let session: ClaudeSession
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
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
        } label: {
            SessionRowView(session: session)
                .contentShape(Rectangle())
                .onTapGesture {
                    activateTerminal(for: session.pid)
                }
        }
        // Defeat the default opaque row background
        .listRowBackground(Color.clear)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
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
        if let app = NSRunningApplication(processIdentifier: appPid) {
            app.activate()
        }
    }
}
