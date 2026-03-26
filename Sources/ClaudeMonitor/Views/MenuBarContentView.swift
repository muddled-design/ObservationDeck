import SwiftUI

/// Wraps SessionListView for the menu bar popover, adding a title bar and detach button.
struct MenuBarContentView: View {
    let store: SessionStore
    let hookInstaller: HookInstaller
    var onDetach: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Observation Deck")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button(action: onDetach) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Detach to floating window")

                Button(action: { store.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(Color(white: 0.5).opacity(0.06))
            )

            SessionListView(store: store, hookInstaller: hookInstaller)
        }
        .frame(width: 420, height: 500)
    }
}

