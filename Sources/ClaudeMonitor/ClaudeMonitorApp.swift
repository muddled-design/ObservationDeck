import SwiftUI
import AppKit

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            SessionListView(store: store)
                .onAppear { store.startPolling() }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button(action: { store.refresh() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .help("Refresh now")
                    }
                }
                .background(WindowAccessor())
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 600)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true

            // Glass chrome: transparent titlebar merges with the content area
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden

            // This is what actually enables NSVisualEffectView underneath SwiftUI
            window.isOpaque = false
            window.backgroundColor = .clear

            // Standard unified look — blurs content behind the entire window
            if let contentView = window.contentView {
                let effectView = NSVisualEffectView()
                effectView.material = .hudWindow        // deep, rich blur
                effectView.blendingMode = .behindWindow
                effectView.state = .active
                effectView.wantsLayer = true
                effectView.layer?.cornerRadius = 10
                effectView.frame = contentView.bounds
                effectView.autoresizingMask = [.width, .height]
                contentView.addSubview(effectView, positioned: .below, relativeTo: nil)
            }

            // Rounded window corners (matches the NSVisualEffectView radius)
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 10
            window.contentView?.layer?.masksToBounds = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
