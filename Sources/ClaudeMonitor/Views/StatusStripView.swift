import SwiftUI

/// A bar pinned to the bottom of the screen divided into equal sections,
/// one per active Claude session. Tapping a section switches to that terminal.
struct StatusStripView: View {
    let store: SessionStore
    let onTap: () -> Void

    var body: some View {
        let sessions = store.sessions.filter { $0.status != .finished }

        GeometryReader { geo in
            if sessions.isEmpty {
                Rectangle()
                    .fill(Color(white: 0.5).opacity(0.4))
                    .onTapGesture(perform: onTap)
            } else {
                HStack(spacing: 1) {
                    ForEach(sessions) { session in
                        SessionSegment(
                            session: session,
                            width: (geo.size.width - CGFloat(sessions.count - 1)) / CGFloat(sessions.count)
                        )
                    }
                }
            }
        }
    }
}

private struct SessionSegment: View {
    let session: ClaudeSession
    let width: CGFloat

    @State private var pulsing = false

    private var isUrgent: Bool { session.status == .needsInput || session.status == .questionAsked }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: session.status.nsColor))

            Text(session.title ?? session.projectName)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 2)
        }
        .frame(width: width)
        .opacity(isUrgent ? (pulsing ? 0.25 : 1.0) : 1.0)
        .onTapGesture {
            activateTerminal(for: session.pid)
        }
        .task(id: isUrgent) {
            guard isUrgent else {
                withAnimation(.easeOut(duration: 0.3)) { pulsing = false }
                return
            }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.7)) { pulsing = true }
                try? await Task.sleep(for: .seconds(0.7))
                withAnimation(.easeInOut(duration: 0.7)) { pulsing = false }
                try? await Task.sleep(for: .seconds(0.7))
            }
        }
    }
}
