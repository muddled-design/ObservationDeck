import SwiftUI

/// Banner that prompts the user to install hooks for real-time status updates.
struct HookSetupBanner: View {
    let installer: HookInstaller
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            switch installer.state {
            case .notInstalled:
                bannerContent(
                    icon: "bolt.badge.clock",
                    title: "Enable real-time status",
                    message: "Install hooks to see live session status instead of heuristic detection.",
                    actionLabel: "Install Hooks",
                    action: { installer.install() }
                )

            case .justInstalled:
                bannerContent(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "Hooks installed",
                    message: "Real-time status is active. New sessions will report live status.",
                    actionLabel: "Dismiss",
                    action: { withAnimation { dismissed = true } }
                )

            case .failed(let error):
                bannerContent(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange,
                    title: "Hook installation failed",
                    message: error,
                    actionLabel: "Retry",
                    action: { installer.install() }
                )

            case .checking, .installed:
                EmptyView()
            }
        }
    }

    private func bannerContent(
        icon: String,
        iconColor: Color = .accentColor,
        title: String,
        message: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(actionLabel, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}
