---
name: ClaudeMonitor project context
description: Architecture, design decisions, and UI conventions for the Claude Monitor macOS floating app
type: project
---

macOS floating monitor app (SwiftUI + AppKit, Swift Package, no Xcode project file).
Build: `swift build` from repo root. Entry point: `Sources/ClaudeMonitor/ClaudeMonitorApp.swift`.

**Architecture**
- `ClaudeMonitorApp` — app entry, `WindowAccessor` NSViewRepresentable for window chrome
- `SessionStore` (@Observable) — drives all state
- Views: `SessionListView` → `SessionDisclosureRow` → `SessionRowView` + `ChildProcessRow`
- `StatusBadge` — status pill component
- `SessionStatus` enum — owns all color/icon/label semantics

**Established design decisions (March 2026)**
- Glass background: `NSVisualEffectView` material `.hudWindow`, blending `.behindWindow`, injected below SwiftUI content via `WindowAccessor`. Window is `isOpaque = false`, `backgroundColor = .clear`. Corner radius 10pt on both `NSVisualEffectView` and `contentView` layer.
- Titlebar: `titlebarAppearsTransparent = true`, `titleVisibility = .hidden` — no visible title string, toolbar refresh button only.
- List: `ScrollView` + `LazyVStack` (NOT SwiftUI `List`) — avoids opaque `NSScrollView` background fighting the glass. `listRowBackground(.clear)` was set but LazyVStack doesn't need it; pattern is to never use `List` with alternating backgrounds on glass windows.
- Session cards: `RoundedRectangle` fill `Color(white: 0.5).opacity(0.07)` + `strokeBorder` opacity 0.10, cornerRadius 8. Padding `.horizontal(8)`.
- Left accent strip: 2.5pt wide `RoundedRectangle`, per-status `accentColor` from `SessionStatus`. This is the primary glance signal.
- `StatusBadge`: capsule pill with icon + label text, 9pt semibold, `glowColor` background (14% opacity), 0.5pt stroke border at 25% opacity. NOT just a dot.
- Finished sessions: `opacity(0.6)` on the row, gray accent strip.
- Status bar footer: `.bar` material, hairline separator, session count in a capsule pill.
- Colors: hand-picked HSB values in `SessionStatus.color` — not system `.green`/`.orange`. Running: `hue 0.37`, NeedsInput: `hue 0.09`. Each status has `.color`, `.glowColor`, `.accentColor`.
- Empty state: custom `VStack` (not `ContentUnavailableView`) for full style control.
- `SessionDisclosureRow` is its own `View` with `@State private var isExpanded` — keeps expand state per-session and avoids the DisclosureGroup being reset on list rebuild.

**Window behavior**
- Level: `.floating`, collectionBehavior: `[.canJoinAllSpaces, .fullScreenAuxiliary]`
- `isMovableByWindowBackground = true`
- Default size 420x600, `.windowResizability(.contentSize)`
