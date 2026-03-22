import SwiftUI

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(status.color)
                .symbolEffect(.pulse, options: .repeating, isActive: status == .running)

            Text(status.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(status.glowColor)
        )
        .overlay(
            Capsule()
                .strokeBorder(status.color.opacity(0.25), lineWidth: 0.5)
        )
    }
}
