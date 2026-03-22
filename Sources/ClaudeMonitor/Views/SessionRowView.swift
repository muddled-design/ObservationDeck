import SwiftUI

struct SessionRowView: View {
    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 0) {
            // Left accent strip — fastest glance signal when scanning the list
            RoundedRectangle(cornerRadius: 1.5)
                .fill(session.status.accentColor)
                .frame(width: 2.5)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(session.status == .finished ? .secondary : .primary)

                    Text(abbreviatedPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(session.cwd)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    StatusBadge(status: session.status)

                    Text(TimeFormatter.format(session.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
        }
        .opacity(session.status == .finished ? 0.6 : 1.0)
    }

    private var displayTitle: String {
        if let name = session.title {
            return "\(name) · \(session.projectName)"
        }
        return session.projectName
    }

    private var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if session.cwd.hasPrefix(home) {
            return "~" + session.cwd.dropFirst(home.count)
        }
        return session.cwd
    }
}
