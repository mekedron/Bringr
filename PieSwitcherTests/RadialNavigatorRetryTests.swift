import CoreGraphics
import XCTest
@testable import PieSwitcher

/// Exercises the empty-sub-wheel retry (Bringr-93j.31): the live window scan can
/// momentarily return nothing right after the reveal un-hides an app, and the
/// navigator must rebuild the sub-wheel on the next hover instead of sticking empty.
/// Kept in its own file (like the other navigator topic suites) to stay within the
/// lint length limits. `FakeWindowSystem` is reused as the window-system double.
@MainActor
final class RadialNavigatorRetryTests: XCTestCase {

    /// First resolve races empty (post-reveal scan before the un-hide lands); the
    /// second returns the window — re-hovering the same app must fill the sub-wheel.
    func testEmptyWindowScanIsRetriedNotStuckEmpty() {
        var resolveCount = 0
        let chrome = MenuNode(
            id: MenuNodeID("app:10"), title: "Chrome", action: .expand,
            representedApp: AppID(pid: 10),
            children: .dynamic {
                resolveCount += 1
                return resolveCount == 1 ? [] : [
                    MenuNode(id: MenuNodeID("w11"), title: "Inbox",
                             action: .focusWindow(WindowID(app: AppID(pid: 10), token: 11)))
                ]
            }
        )
        let navigator = RadialNavigator(windowControl: WindowController(system: fake()))
        navigator.open(appNodes: [chrome])

        navigator.updateHover(.slice(level: 0, index: 0)) // scan races empty
        XCTAssertFalse(navigator.hasWindowSubWheel)
        XCTAssertEqual(navigator.expandedAppIndex, 0)     // reveal still tracked for restore

        navigator.updateHover(.slice(level: 0, index: 0)) // retry: scan now settles
        XCTAssertTrue(navigator.hasWindowSubWheel)
        XCTAssertEqual(navigator.rings[1].nodes.map(\.title), ["Inbox"])
    }

    /// A populated sub-wheel stays idempotent — re-hovering the same app must not
    /// re-resolve, so the retry path can't churn a settled wheel.
    func testPopulatedSubWheelStaysIdempotent() {
        var resolveCount = 0
        let chrome = MenuNode(
            id: MenuNodeID("app:10"), title: "Chrome", action: .expand,
            representedApp: AppID(pid: 10),
            children: .dynamic {
                resolveCount += 1
                return [MenuNode(id: MenuNodeID("w11"), title: "Inbox",
                                 action: .focusWindow(WindowID(app: AppID(pid: 10), token: 11)))]
            }
        )
        let navigator = RadialNavigator(windowControl: WindowController(system: fake()))
        navigator.open(appNodes: [chrome])

        navigator.updateHover(.slice(level: 0, index: 0))
        navigator.updateHover(.slice(level: 0, index: 0))

        XCTAssertEqual(resolveCount, 1) // second hover was a no-op
        XCTAssertTrue(navigator.hasWindowSubWheel)
    }

    private func fake() -> FakeWindowSystem {
        FakeWindowSystem(
            apps: [FakeWindowSystem.AppState(
                id: AppID(pid: 10), hidden: false,
                windows: [FakeWindowSystem.WindowState(
                    id: WindowID(app: AppID(pid: 10), token: 11), minimized: false)]
            )],
            frontmost: AppID(pid: 10)
        )
    }
}
