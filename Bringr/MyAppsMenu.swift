import CoreGraphics
import Foundation

/// The top-level wheel composed from the user's curated "My Apps" list
/// (Bringr-93j.41) — the join point of the list model (Bringr-93j.37), the
/// not-running icon (Bringr-93j.38), and the launch action (Bringr-93j.39).
///
/// For each listed app, in the user's manual order, it produces one of two nodes:
/// - running with windows on the summon screen → the same expand-to-windows node the
///   raw wheel builds (`WindowSwitcherMenu.appNode`), so hovering drills into its live
///   windows sub-wheel and committing focuses;
/// - not running, or running with no windows on this screen → a launch node carrying the
///   bundle id, so committing starts/raises the app (Bringr-93j.39) and the slice still
///   shows the on-disk icon (Bringr-93j.38).
///
/// An empty list falls straight through to the unchanged full wheel, so a user who has
/// curated nothing sees exactly the current behavior. Appending the *other* running apps
/// after the pinned block is a separate, defaulted-on toggle (Bringr-93j.42); this layer
/// shows only the curated apps.
@MainActor
struct MyAppsMenu: MenuDefinition {
    private let enumerator: WindowEnumerator
    /// The raw all-running-apps wheel, reused for the empty-list fallback.
    private let fallback: WindowSwitcherMenu
    /// The curated list, read through a closure so each summon picks up the persisted
    /// Preferences value fresh (mirroring `WindowEnumerator`'s sort-order closures); tests
    /// inject a fixed list.
    private let curatedApps: () -> [CuratedApp]
    /// Resolves a bundle id to its running instance's pid, behind a closure so the
    /// running-vs-launch decision is unit-testable without a live `NSRunningApplication`
    /// lookup; the default consults the live workspace.
    private let runningPID: (String) -> pid_t?

    init(
        enumerator: WindowEnumerator,
        curatedApps: @escaping () -> [CuratedApp] = { CuratedApps.current() },
        runningPID: @escaping (String) -> pid_t? = {
            CuratedApp.runningApplication(forBundleIdentifier: $0)?.processIdentifier
        }
    ) {
        self.enumerator = enumerator
        self.fallback = WindowSwitcherMenu(enumerator: enumerator)
        self.curatedApps = curatedApps
        self.runningPID = runningPID
    }

    func makeRoot(onScreen screenBounds: CGRect?) -> MenuNode {
        let curated = curatedApps()
        // Empty list → the current full wheel, unchanged (AC: "an empty list reproduces
        // the current wheel"). Decided per summon, since `makeRoot` is called fresh each
        // time and the list is read above.
        guard !curated.isEmpty else { return fallback.makeRoot(onScreen: screenBounds) }

        let enumerator = self.enumerator
        let runningPID = self.runningPID
        // Capture `screenBounds` so the ring and every sub-wheel stay locked to the summon
        // display (Bringr-93j.30), matching the raw wheel.
        return MenuNode(
            id: MenuNodeID("root:apps"),
            title: "Applications",
            action: .expand,
            children: .dynamic {
                let live = enumerator.enumerate(onScreen: screenBounds)
                return curated.map {
                    Self.node(
                        for: $0, live: live, onScreen: screenBounds,
                        enumerator: enumerator, runningPID: runningPID
                    )
                }
            }
        )
    }

    /// One curated entry's node: the running-with-windows app node when its running pid
    /// owns at least one window in the screen-scoped `live` enumeration, otherwise a launch
    /// node. Resolving against `live` (already filtered to the summon screen) means an app
    /// running only on another display becomes a launch node here — consistent with the
    /// rest of the screen-scoped wheel (Bringr-93j.30).
    private static func node(
        for app: CuratedApp, live: [AppWindows], onScreen screenBounds: CGRect?,
        enumerator: WindowEnumerator, runningPID: (String) -> pid_t?
    ) -> MenuNode {
        if let pid = runningPID(app.bundleIdentifier),
           let appWindows = live.first(where: { $0.id.pid == pid }) {
            return WindowSwitcherMenu.appNode(
                appWindows, onScreen: screenBounds, enumerator: enumerator,
                bundleIdentifier: app.bundleIdentifier
            )
        }
        return MenuNode(
            id: MenuNodeID("launch:\(app.bundleIdentifier)"),
            title: app.name,
            action: .launchApp(bundleIdentifier: app.bundleIdentifier),
            bundleIdentifier: app.bundleIdentifier
        )
    }
}
