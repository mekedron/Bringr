import AppKit
import SwiftUI

/// Pre-warmed overlay that hosts the radial wheel. Created once at launch and
/// shown/hidden — never rebuilt on the summon hot path (the < 16 ms budget).
///
/// A borderless, transparent, non-activating floating panel: it floats above the
/// app the user summoned it over without activating Bringr or deactivating that
/// app — which would disturb the very window state the switcher must preserve.
final class RadialMenuWindow: NSPanel {
    @MainActor
    init(contentSize: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }
}

/// Owns the pre-warmed overlay window and resolves the menu tree for each summon.
///
/// The window and its SwiftUI host are built once in `init` (the pre-warm); a
/// summon only resolves the live tree, repositions the window at the cursor, and
/// orders it in — no allocation on the hot path. `slices` is published so the
/// pre-built `RadialMenuView` re-renders when a new summon swaps the contents.
@MainActor
final class RadialMenuController: ObservableObject {
    /// The resolved top-level nodes shown as slices for the current summon.
    @Published private(set) var slices: [MenuNode] = []
    /// Whether the overlay is currently on screen.
    @Published private(set) var isVisible = false

    let geometry: RadialGeometry

    private let registry: MenuRegistry
    private let window: RadialMenuWindow

    init(registry: MenuRegistry, geometry: RadialGeometry = .default) {
        self.registry = registry
        self.geometry = geometry
        self.window = RadialMenuWindow(
            contentSize: CGSize(width: geometry.diameter, height: geometry.diameter)
        )
        // Pre-warm the SwiftUI host now so summon never allocates it.
        window.contentView = NSHostingView(rootView: RadialMenuView(controller: self))
    }

    /// Show the menu registered for `trigger` centred at `cursor` (the global
    /// mouse location). Resolves the tree fresh so the wheel reflects live state.
    func summon(trigger: MenuTrigger, at cursor: CGPoint) {
        guard let root = registry.makeMenu(for: trigger) else { return }
        slices = root.resolvedChildren()
        let origin = RadialMenuPlacement.windowOrigin(forCursor: cursor, windowSize: window.frame.size)
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        isVisible = true
    }

    /// Summon if hidden, dismiss if shown. The menu-bar entry point and a future
    /// click-to-stay trigger both reuse this.
    func toggle(trigger: MenuTrigger, at cursor: CGPoint) {
        if isVisible {
            dismiss()
        } else {
            summon(trigger: trigger, at: cursor)
        }
    }

    /// Hide the overlay. Selection and the reveal-strategy restore land in later
    /// stories; v1 simply orders the window out.
    func dismiss() {
        window.orderOut(nil)
        isVisible = false
    }
}
