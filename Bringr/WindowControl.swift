import AppKit
import ApplicationServices
import Foundation

/// Identifies a running application by its process id.
struct AppID: Hashable, Sendable {
    let pid: pid_t
}

/// Identifies a window. `token` is an opaque, system-assigned handle (callers
/// treat it as opaque); `app` ties the window to its owning application.
///
/// v1's live system assigns the token by enumeration index. The richer,
/// cross-restart-stable identity lives with the enumeration service (US-003);
/// `WindowController` only relies on `WindowID` being `Hashable`, so that
/// refinement is additive.
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
    /// Apps that are candidates for control (regular apps, excluding Bringr).
    func runningApps() -> [AppID]
    /// Windows of `app`, front-to-back.
    func windows(of app: AppID) -> [WindowID]
    /// The frontmost app, if any.
    func frontmostApp() -> AppID?

    func isHidden(_ app: AppID) -> Bool
    func setHidden(_ app: AppID, _ hidden: Bool)
    func activate(_ app: AppID)

    func isMinimized(_ window: WindowID) -> Bool
    func setMinimized(_ window: WindowID, _ minimized: Bool)
    /// Bring `window` to the front within its application.
    func raise(_ window: WindowID)
    /// Make `window` main and focused (its app should already be active).
    func focusWindow(_ window: WindowID)
}

/// Low-level window/app control primitives that the reveal strategies (US-013)
/// and selection (US-012) build on.
///
/// Every mutating primitive first captures the pre-mutation state of the scope
/// it touches — app visibility/order, or one app's window minimized-state/order
/// — exactly once per session. `restore()` replays that captured baseline, so it
/// returns to the pre-summon state no matter how many isolate/re-target calls
/// happened in between.
@MainActor
final class WindowController {
    private struct AppSnapshot {
        let id: AppID
        let wasHidden: Bool
    }

    private struct WindowSnapshot {
        let id: WindowID
        let wasMinimized: Bool
    }

    private struct Session {
        var didCaptureApps = false
        var frontmostBefore: AppID?
        var appBaseline: [AppSnapshot] = []
        var windowBaseline: [AppID: [WindowSnapshot]] = [:]
    }

    private let system: WindowControlling
    private var session: Session?

    init(system: WindowControlling? = nil) {
        self.system = system ?? LiveWindowSystem()
    }

    /// Whether a capture/restore session is currently open.
    var hasActiveSession: Bool { session != nil }

    // MARK: - Primitives

    /// Raise `window` and move focus to it: activate its app, bring the window
    /// to the front, and make it main/focused. (AC1)
    func raiseAndFocus(_ window: WindowID) {
        system.activate(window.app)
        system.raise(window)
        system.focusWindow(window)
    }

    /// Hide every app except `target`, capturing app visibility/order first so
    /// `restore()` can put them back exactly. (AC2)
    func hideOtherApps(besides target: AppID) {
        captureAppBaselineIfNeeded()
        if system.isHidden(target) {
            system.setHidden(target, false)
        }
        for app in system.runningApps() where app != target && !system.isHidden(app) {
            system.setHidden(app, true)
        }
    }

    /// Hide every window of `target`'s app except `target`, capturing that app's
    /// window state/order first so `restore()` can put them back exactly. (AC3)
    func hideOtherWindows(besides target: WindowID) {
        captureWindowBaselineIfNeeded(for: target.app)
        if system.isMinimized(target) {
            system.setMinimized(target, false)
        }
        for window in system.windows(of: target.app)
        where window != target && !system.isMinimized(window) {
            system.setMinimized(window, true)
        }
    }

    /// Restore every app/window touched this session to its pre-summon
    /// visibility and ordering, then end the session. Safe to call with no
    /// active session. (AC5)
    func restore() {
        guard let session else { return }

        // 1. App visibility first, so windows are operated on while their app is shown.
        for snapshot in session.appBaseline {
            system.setHidden(snapshot.id, snapshot.wasHidden)
        }

        // 2. Per-app window minimized-state, then re-raise back-to-front so the
        //    original front window ends up on top again.
        for (_, windows) in session.windowBaseline {
            for snapshot in windows {
                system.setMinimized(snapshot.id, snapshot.wasMinimized)
            }
            for snapshot in windows.reversed() where !snapshot.wasMinimized {
                system.raise(snapshot.id)
            }
        }

        // 3. Frontmost app last, restoring app-level z-order and focus.
        if let frontmost = session.frontmostBefore {
            system.activate(frontmost)
        }

        self.session = nil
    }

    // MARK: - Baseline capture (AC4)

    private func captureAppBaselineIfNeeded() {
        if session == nil { session = Session() }
        guard session?.didCaptureApps == false else { return }
        session?.didCaptureApps = true
        session?.frontmostBefore = system.frontmostApp()
        session?.appBaseline = system.runningApps().map {
            AppSnapshot(id: $0, wasHidden: system.isHidden($0))
        }
    }

    private func captureWindowBaselineIfNeeded(for app: AppID) {
        if session == nil { session = Session() }
        guard session?.windowBaseline[app] == nil else { return }
        session?.windowBaseline[app] = system.windows(of: app).map {
            WindowSnapshot(id: $0, wasMinimized: system.isMinimized($0))
        }
    }
}

/// Live `WindowControlling` backed by `NSRunningApplication` (app visibility and
/// activation) and the Accessibility API (per-window state and control).
///
/// Hiding a single window uses AX minimize, the only reversible per-window hide
/// the API offers; `restore()` un-minimizes it. AX element references are cached
/// by `WindowID` as windows are enumerated.
@MainActor
final class LiveWindowSystem: WindowControlling {
    private var elementCache: [WindowID: AXUIElement] = [:]
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    func runningApps() -> [AppID] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != selfPID }
            .map { AppID(pid: $0.processIdentifier) }
    }

    func windows(of app: AppID) -> [WindowID] {
        let appElement = AXUIElementCreateApplication(app.pid)
        guard let axWindows = copyWindows(appElement) else { return [] }

        var ids: [WindowID] = []
        for axWindow in axWindows {
            let id = WindowID(app: app, token: ids.count)
            elementCache[id] = axWindow
            ids.append(id)
        }
        return ids
    }

    func frontmostApp() -> AppID? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != selfPID else { return nil }
        return AppID(pid: app.processIdentifier)
    }

    func isHidden(_ app: AppID) -> Bool {
        runningApplication(app)?.isHidden ?? false
    }

    func setHidden(_ app: AppID, _ hidden: Bool) {
        guard let running = runningApplication(app) else { return }
        if hidden {
            running.hide()
        } else {
            running.unhide()
        }
    }

    func activate(_ app: AppID) {
        runningApplication(app)?.activate()
    }

    func isMinimized(_ window: WindowID) -> Bool {
        guard let element = elementCache[window] else { return false }
        return boolAttribute(element, kAXMinimizedAttribute)
    }

    func setMinimized(_ window: WindowID, _ minimized: Bool) {
        guard let element = elementCache[window] else { return }
        setBool(element, kAXMinimizedAttribute, minimized)
    }

    func raise(_ window: WindowID) {
        guard let element = elementCache[window] else { return }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func focusWindow(_ window: WindowID) {
        guard let element = elementCache[window] else { return }
        setBool(element, kAXMainAttribute, true)
        setBool(element, kAXFocusedAttribute, true)
    }

    // MARK: - Helpers

    private func runningApplication(_ app: AppID) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: app.pid)
    }

    private func copyWindows(_ appElement: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &value
        )
        guard result == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let boolValue = value as? Bool else { return false }
        return boolValue
    }

    private func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
        let cfValue: CFBoolean = value ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(element, attribute as CFString, cfValue)
    }
}
