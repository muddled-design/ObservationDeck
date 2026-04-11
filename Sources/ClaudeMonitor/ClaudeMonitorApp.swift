import SwiftUI
import AppKit

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverHostingController: NSViewController?  // kept alive to prevent animation crash
    private var store: SessionStore!
    private var hookInstaller: HookInstaller!
    private var detachedWindow: NSWindow?
    private var stripWindow: NSWindow?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = SessionStore()
        hookInstaller = HookInstaller()
        store.startPolling()
        hookInstaller.check()

        // Status bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(for: nil)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 500)
        popover.behavior = .transient
        popover.animates = false

        let contentView = MenuBarContentView(
            store: store,
            hookInstaller: hookInstaller,
            onDetach: { [weak self] in self?.detachToWindow() }
        )
        let hc = NSHostingController(rootView: contentView)
        popoverHostingController = hc   // retain strongly — prevents animation use-after-free
        popover.contentViewController = hc

        // Update icon color on each refresh
        store.onRefresh = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.updateStatusIcon(for: self.store.worstStatus)
            }
        }

        setupStripWindow()
    }

    // MARK: - Status Strip

    private func setupStripWindow() {
        let screen = NSScreen.main ?? NSScreen.screens[0]

        let stripHeight: CGFloat = 8
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: stripHeight
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: 1001)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        let view = StatusStripView(store: store) { [weak self] in
            self?.showDetailWindow()
        }
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        stripWindow = window
    }

    func showDetailWindow() {
        detachToWindow()
    }

    // MARK: - Status Icon

    private func updateStatusIcon(for status: SessionStatus?) {
        let color = status?.nsColor ?? NSColor(white: 0.55, alpha: 1)
        statusItem.button?.image = makeStatusIcon(color: color)
    }

    private func makeStatusIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.midX
            let cy = rect.midY

            // Eye shape — almond, fills most of the icon
            let eyeWidth: CGFloat = 16
            let eyeHeight: CGFloat = 7.5
            let eyePath = NSBezierPath()
            eyePath.move(to: NSPoint(x: cx - eyeWidth / 2, y: cy))
            eyePath.curve(to: NSPoint(x: cx + eyeWidth / 2, y: cy),
                        controlPoint1: NSPoint(x: cx - eyeWidth / 4, y: cy + eyeHeight),
                        controlPoint2: NSPoint(x: cx + eyeWidth / 4, y: cy + eyeHeight))
            eyePath.curve(to: NSPoint(x: cx - eyeWidth / 2, y: cy),
                        controlPoint1: NSPoint(x: cx + eyeWidth / 4, y: cy - eyeHeight),
                        controlPoint2: NSPoint(x: cx - eyeWidth / 4, y: cy - eyeHeight))
            eyePath.close()

            // Fill entire eye with status color
            color.setFill()
            eyePath.fill()

            // Small dark pupil dot in center for the "eye" look
            let pupilSize: CGFloat = 4
            let pupilRect = NSRect(x: cx - pupilSize / 2, y: cy - pupilSize / 2,
                                   width: pupilSize, height: pupilSize)
            (color.blended(withFraction: 0.6, of: .black) ?? .black).setFill()
            NSBezierPath(ovalIn: pupilRect).fill()

            // Thin outline
            NSColor.labelColor.withAlphaComponent(0.5).setStroke()
            eyePath.lineWidth = 0.75
            eyePath.stroke()

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        // If detached window is visible, hide it back to menu bar
        if let window = detachedWindow, window.isVisible {
            collapseToMenuBar()
            return
        }

        // Only open — .transient behavior closes the popover when clicking outside
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func collapseToMenuBar() {
        detachedWindow?.orderOut(nil)
    }

    // NSWindowDelegate: intercept the red-X so it hides rather than closes (avoids animation crash)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - Detach to Floating Window

    private func detachToWindow() {
        // If already created, just show it
        if let existing = detachedWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SessionListView(store: store, hookInstaller: hookInstaller)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("detachedMonitor")
        window.center()
        window.title = "Observation Deck"
        window.contentViewController = hostingController
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.delegate = self   // intercept windowShouldClose

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        detachedWindow = window   // kept for lifetime of app — never closed, only hidden
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

            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden

            window.isOpaque = false
            window.backgroundColor = .clear

            if let contentView = window.contentView {
                let effectView = NSVisualEffectView()
                effectView.material = .hudWindow
                effectView.blendingMode = .behindWindow
                effectView.state = .active
                effectView.wantsLayer = true
                effectView.layer?.cornerRadius = 10
                effectView.frame = contentView.bounds
                effectView.autoresizingMask = [.width, .height]
                contentView.addSubview(effectView, positioned: .below, relativeTo: nil)
            }

            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 10
            window.contentView?.layer?.masksToBounds = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
