import CoreGraphics
import Foundation

/// Identifies a running application by its process id.
struct AppID: Hashable, Sendable {
    let pid: pid_t
}

/// Identifies a window. `token` is the window's `kCGWindowNumber` — the same value the
/// enumeration service (US-003) uses — so a `WindowID` from `WindowEnumerator` and one
/// from `LiveWindowSystem` for the same window are equal and interchangeable. `app` ties
/// it to its owning application; `WindowController` only relies on `Hashable`.
struct WindowID: Hashable, Sendable {
    let app: AppID
    let token: Int
}

/// The window-system operations `WindowController` needs, behind a seam so the
/// orchestration logic can be unit-tested with an in-memory fake — no live
/// Accessibility calls and no real windows during tests. Mirrors the injectable
/// design of `PermissionsManager`.
@MainActor
protocol WindowControlling {
    /// Apps that are candidates for control (regular apps, excluding PieSwitcher).
    func runningApps() -> [AppID]
    /// Windows of `app`, front-to-back.
    func windows(of app: AppID) -> [WindowID]
    /// The frontmost app, if any.
    func frontmostApp() -> AppID?

    func isHidden(_ app: AppID) -> Bool
    func setHidden(_ app: AppID, _ hidden: Bool)
    func activate(_ app: AppID)
    /// Reopen `app` like a Dock click: a windowless app opens a fresh window, a windowed
    /// one just comes forward (Bringr-93j.61). Distinct from `activate`, which only raises
    /// an app and must never spawn a window — it runs on restore paths. Used by `commit(_:)`
    /// when the chosen app turns out to have no window to focus.
    func reopen(_ app: AppID)

    func isMinimized(_ window: WindowID) -> Bool
    func setMinimized(_ window: WindowID, _ minimized: Bool)
    /// Bring `window` to the front within its application.
    func raise(_ window: WindowID)
    /// Make `window` main and focused (its app should already be active).
    func focusWindow(_ window: WindowID)
    /// Raise and focus a window that lives on another Space, switching to that Space
    /// (Bringr-93j.54). The Accessibility primitives can't: `kAXWindowsAttribute` doesn't
    /// enumerate other Spaces, so there's no cached AX element to act on. Used only as the
    /// commit-time fallback for a window absent from its app's AX window list, so the proven
    /// AX path for same-Space windows is untouched.
    func raiseAcrossSpaces(_ window: WindowID)
    /// The window's frame in AppKit-global coordinates (bottom-left origin, y-up),
    /// or `nil` if it can't be resolved — used to cut the target out of the dim
    /// overlay (US-013 dim-others).
    func frame(of window: WindowID) -> CGRect?

    /// The window's top-left in its native (y-down) space, or `nil`. Captured before
    /// parking a window off-screen so it can be moved back exactly (Bringr-93j.24);
    /// not flipped to AppKit-global like `frame(of:)`, since capture and park share it.
    func position(of window: WindowID) -> CGPoint?
    /// Move `window`'s top-left to `point` (same space as `position(of:)`). Instant,
    /// unlike AX minimize's slow genie animation — the window-level hide-others reveal
    /// parks the app's other windows off-screen with this instead (Bringr-93j.24).
    func setPosition(_ window: WindowID, _ point: CGPoint)
    /// Park `window` off-screen at the window level (the hide-others reveal's fast,
    /// genie-free hide — Bringr-93j.24). Unlike a plain `setPosition`, the live system
    /// moves the window horizontally toward the side whose extreme display is tallest and
    /// keeps its Y, so macOS can't re-home it onto a shorter/offset display and clamp its
    /// height (Bringr-93j.81 — the per-hover ~250px shrink). `restore` moves it back via
    /// `setPosition`/`setSize` to its captured frame.
    func park(_ window: WindowID)

    /// The window's size, or `nil`. Captured with `position(of:)` so a parked window's
    /// exact frame can be restored: macOS clamps a window's height when it's moved off
    /// the bottom of every screen, so position alone leaves it shorter (Bringr-93j.28).
    func size(of window: WindowID) -> CGSize?
    /// Set `window`'s size (anchored at its top-left), undoing that off-screen height
    /// clamp on restore (Bringr-93j.28).
    func setSize(_ window: WindowID, _ size: CGSize)
}

/// Decides *where* the window-level hide-others reveal parks a window off-screen.
///
/// macOS refuses to let a window's title bar leave every display: park it far to one
/// side and the window server slides it back until a sliver overlaps the *extreme*
/// display in that direction, then clamps its height to that display's visible height.
/// Parking far-right therefore re-homed a tall window onto the rightmost (often the
/// laptop, shorter and vertically offset) display and shrank it — and once clamped the
/// height never fully restored, so each hover lost ~250px (Bringr-93j.81).
///
/// The fix is to choose the side whose extreme display is *tallest*. On the common
/// one/two-display setups the tallest extreme is the tallest display overall, so a tall
/// window lands on a display at least as tall as itself and is never clamped. The caller
/// keeps the window's Y, so its vertical extent is unchanged on the target display too.
enum WindowParkGeometry {
    /// How far beyond a display's outer edge to push a parked window; macOS slides it
    /// back to a title-bar sliver regardless, so any value clear of the desktop works.
    static let offScreenInset: CGFloat = 50_000

    /// The off-screen X to park at, given the displays' frames (AppKit or AX — only the
    /// space-agnostic X-extents and heights are read). Falls back to a far-right value
    /// when no displays are reported.
    static func parkedX(screenFrames: [CGRect]) -> CGFloat {
        guard let leftMost = screenFrames.min(by: { $0.minX < $1.minX }),
              let rightMost = screenFrames.max(by: { $0.maxX < $1.maxX }) else {
            return offScreenInset
        }
        if leftMost.height >= rightMost.height {
            return leftMost.minX - offScreenInset
        }
        return rightMost.maxX + offScreenInset
    }
}
