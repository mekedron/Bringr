import XCTest
@testable import Bringr

/// In-memory `WindowControlling` for tests: models app visibility/z-order and
/// per-app window minimized-state/z-order, with no live system dependency.
@MainActor
final class FakeWindowSystem: WindowControlling {
    enum Operation: Equatable {
        case windows(AppID)
        case setHidden(AppID, Bool)
        case activate(AppID)
        case setMinimized(WindowID, Bool)
        case raise(WindowID)
        case focusWindow(WindowID)
    }

    final class WindowState {
        let id: WindowID
        var minimized: Bool

        init(id: WindowID, minimized: Bool) {
            self.id = id
            self.minimized = minimized
        }
    }

    final class AppState {
        let id: AppID
        var hidden: Bool
        var windows: [WindowState]

        init(id: AppID, hidden: Bool, windows: [WindowState]) {
            self.id = id
            self.hidden = hidden
            self.windows = windows
        }
    }

    var apps: [AppState]
    var frontmost: AppID?
    private(set) var focusedWindow: WindowID?
    /// Apps passed to `activate` / `windows(of:)`, in call order — lets tests assert
    /// commit ordering (no prior-frontmost re-activation; target cache refreshed).
    private(set) var activationLog: [AppID] = []
    private(set) var enumerationLog: [AppID] = []
    private(set) var operationLog: [Operation] = []

    init(apps: [AppState], frontmost: AppID?) {
        self.apps = apps
        self.frontmost = frontmost
    }

    func clearLog() {
        activationLog = []
        enumerationLog = []
        operationLog = []
    }

    private func appState(_ id: AppID) -> AppState? {
        apps.first { $0.id == id }
    }

    private func windowState(_ id: WindowID) -> WindowState? {
        appState(id.app)?.windows.first { $0.id == id }
    }

    func runningApps() -> [AppID] {
        apps.map { $0.id }
    }

    func windows(of app: AppID) -> [WindowID] {
        enumerationLog.append(app)
        operationLog.append(.windows(app))
        return appState(app)?.windows.map { $0.id } ?? []
    }

    func frontmostApp() -> AppID? {
        frontmost
    }

    func isHidden(_ app: AppID) -> Bool {
        appState(app)?.hidden ?? false
    }

    func setHidden(_ app: AppID, _ hidden: Bool) {
        operationLog.append(.setHidden(app, hidden))
        appState(app)?.hidden = hidden
    }

    func activate(_ app: AppID) {
        activationLog.append(app)
        operationLog.append(.activate(app))
        frontmost = app
        guard let index = apps.firstIndex(where: { $0.id == app }) else { return }
        let state = apps.remove(at: index)
        apps.insert(state, at: 0)
    }

    func isMinimized(_ window: WindowID) -> Bool {
        windowState(window)?.minimized ?? false
    }

    func setMinimized(_ window: WindowID, _ minimized: Bool) {
        operationLog.append(.setMinimized(window, minimized))
        windowState(window)?.minimized = minimized
    }

    func raise(_ window: WindowID) {
        operationLog.append(.raise(window))
        guard let app = appState(window.app),
              let index = app.windows.firstIndex(where: { $0.id == window }) else { return }
        let state = app.windows.remove(at: index)
        app.windows.insert(state, at: 0)
    }

    func focusWindow(_ window: WindowID) {
        operationLog.append(.focusWindow(window))
        focusedWindow = window
    }
}
