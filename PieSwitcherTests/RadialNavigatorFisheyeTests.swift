import CoreGraphics
import XCTest
@testable import PieSwitcher

/// Exercises the US-016 window sub-wheel: app-aligned window arcs, the overflow
/// fisheye, and the empty-outer-sector no-op. Kept in its own file (like
/// `RadialNavigatorCommitTests`) so each navigator test file stays within the lint
/// length limits. `FakeWindowSystem` and `StubEnumerationSource` are reused as the
/// doubles, the same pure-core testing the hover navigation uses.
@MainActor
final class RadialNavigatorFisheyeTests: XCTestCase {

    // MARK: - overflow fisheye

    func testExpandingOverflowAppOpensWithFirstWindowFocused() {
        let fixture = makeOverflowFixture()
        fixture.navigator.open(appNodes: fixture.appNodes)

        fixture.navigator.updateHover(.slice(level: 0, index: 0)) // Chrome: 3 windows, 2 apps

        XCTAssertEqual(fixture.navigator.focusedWindowIndex, 0)
        let appArc = 2 * CGFloat.pi / CGFloat(fixture.appNodes.count)
        let layout = fixture.navigator.rings[1].layout
        XCTAssertEqual(layout.span(ofSliceAt: 0), appArc, accuracy: 0.0001) // focused = one app-arc
        XCTAssertGreaterThan(appArc, layout.span(ofSliceAt: 1))             // others compressed
    }

    func testHoveringAWindowMovesFisheyeFocusAndIsolatesIt() {
        let fixture = makeOverflowFixture()
        fixture.navigator.open(appNodes: fixture.appNodes)
        fixture.navigator.updateHover(.slice(level: 0, index: 0)) // Chrome overflow

        fixture.navigator.updateHover(.slice(level: 1, index: 2)) // third window

        // Both effects fire on the one hover: fisheye focus and window isolation.
        XCTAssertEqual(fixture.navigator.focusedWindowIndex, 2)
        XCTAssertEqual(fixture.navigator.expandedWindowIndex, 2)
        let appArc = 2 * CGFloat.pi / CGFloat(fixture.appNodes.count)
        let layout = fixture.navigator.rings[1].layout
        XCTAssertEqual(layout.span(ofSliceAt: 2), appArc, accuracy: 0.0001)
        XCTAssertLessThan(layout.span(ofSliceAt: 0), appArc) // the rest re-compressed
    }

    func testNonOverflowAppHasNoFisheyeFocus() {
        let fixture = makeFixture()
        fixture.navigator.open(appNodes: fixture.appNodes)

        fixture.navigator.updateHover(.slice(level: 0, index: 0)) // Chrome: 2 windows, 2 apps

        XCTAssertNil(fixture.navigator.focusedWindowIndex)
        let appArc = 2 * CGFloat.pi / CGFloat(fixture.appNodes.count)
        let layout = fixture.navigator.rings[1].layout
        XCTAssertEqual(layout.span(ofSliceAt: 0), appArc, accuracy: 0.0001)
        XCTAssertEqual(layout.span(ofSliceAt: 1), appArc, accuracy: 0.0001)
    }

    func testFisheyeFocusResetsOnReTargetAndCollapse() {
        let fixture = makeOverflowFixture()
        fixture.navigator.open(appNodes: fixture.appNodes)
        fixture.navigator.updateHover(.slice(level: 0, index: 0)) // Chrome overflow
        fixture.navigator.updateHover(.slice(level: 1, index: 2)) // focus 2
        XCTAssertEqual(fixture.navigator.focusedWindowIndex, 2)

        fixture.navigator.updateHover(.slice(level: 0, index: 1)) // Ghostty: 1 window, no overflow
        XCTAssertNil(fixture.navigator.focusedWindowIndex)

        fixture.navigator.updateHover(.slice(level: 0, index: 0)) // back to Chrome → focus resets to 0
        XCTAssertEqual(fixture.navigator.focusedWindowIndex, 0)
        fixture.navigator.updateHover(.none) // collapse to the dead zone
        XCTAssertNil(fixture.navigator.focusedWindowIndex)
    }

    func testRegionUsesStoredRingLayoutForFocusedAndCompressedSlices() {
        let fixture = makeOverflowFixture()
        fixture.navigator.open(appNodes: fixture.appNodes)
        fixture.navigator.updateHover(.slice(level: 0, index: 0)) // Chrome overflow, focus 0

        let layout = fixture.navigator.rings[1].layout
        XCTAssertEqual(fixture.navigator.region(forOffset: layout.sliceCenterOffset(at: 0)),
                       .slice(level: 1, index: 0)) // the focused (full) slice
        XCTAssertEqual(fixture.navigator.region(forOffset: layout.sliceCenterOffset(at: 1)),
                       .slice(level: 1, index: 1)) // a compressed slice
    }

    // MARK: - empty outer sector (windowCount < appCount)

    func testEmptyOuterSectorIsANoOpAndKeepsTheSubWheelOpen() {
        // Ghostty has one window but there are two apps, so its window ring covers only
        // one app-arc (over Ghostty); the opposite app-arc is an empty outer sector.
        let fixture = makeFixture()
        fixture.navigator.open(appNodes: fixture.appNodes)
        fixture.navigator.updateHover(.slice(level: 0, index: 1)) // Ghostty: 1 window
        XCTAssertEqual(fixture.navigator.rings.count, 2)

        // Straight up is Chrome's (app 0) direction, uncovered by Ghostty's lone window.
        let mid1 = fixture.navigator.ringGeometry(forLevel: 1).midRadius
        let region = fixture.navigator.region(forOffset: CGPoint(x: 0, y: -mid1))
        XCTAssertNotEqual(region, .none) // a no-op, not a collapse

        fixture.navigator.updateHover(region)
        XCTAssertEqual(fixture.navigator.rings.count, 2) // sub-wheel stays open
        XCTAssertEqual(fixture.navigator.expandedAppIndex, 1)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let navigator: RadialNavigator
        let appNodes: [MenuNode]
    }

    /// Two apps, Chrome with two windows — window count equals app count, so the
    /// sub-wheel tiles without a fisheye (used for the non-overflow and empty-sector
    /// cases; Ghostty's lone window is fewer than the app count).
    private func makeFixture() -> Fixture {
        makeFixture(chromeWindows: [
            raw(number: 11, pid: 10, name: "Chrome", title: "Inbox"),
            raw(number: 12, pid: 10, name: "Chrome", title: "Docs")
        ], chromeTokens: [11, 12])
    }

    /// Two apps where Chrome has three windows — more windows than apps — so its
    /// sub-wheel overflows and lays out as a US-016 fisheye.
    private func makeOverflowFixture() -> Fixture {
        makeFixture(chromeWindows: [
            raw(number: 11, pid: 10, name: "Chrome", title: "Inbox"),
            raw(number: 12, pid: 10, name: "Chrome", title: "Docs"),
            raw(number: 13, pid: 10, name: "Chrome", title: "Calendar")
        ], chromeTokens: [11, 12, 13])
    }

    private func makeFixture(chromeWindows: [RawWindow], chromeTokens: [Int]) -> Fixture {
        let source = StubEnumerationSource(selfPID: 1, windows: chromeWindows + [
            raw(number: 21, pid: 20, name: "Ghostty", title: "Terminal")
        ])
        let appNodes = WindowSwitcherMenu(enumerator: WindowEnumerator(source: source))
            .makeRoot().resolvedChildren()
        let fake = FakeWindowSystem(
            apps: [
                FakeWindowSystem.AppState(id: AppID(pid: 10), hidden: false,
                                          windows: chromeTokens.map { win(10, $0) }),
                FakeWindowSystem.AppState(id: AppID(pid: 20), hidden: false,
                                          windows: [win(20, 21)])
            ],
            frontmost: AppID(pid: 10)
        )
        let navigator = RadialNavigator(windowControl: WindowController(system: fake))
        return Fixture(navigator: navigator, appNodes: appNodes)
    }

    private func win(_ pid: pid_t, _ token: Int) -> FakeWindowSystem.WindowState {
        FakeWindowSystem.WindowState(id: WindowID(app: AppID(pid: pid), token: token), minimized: false)
    }

    private func raw(number: Int, pid: pid_t, name: String, title: String = "") -> RawWindow {
        RawWindow(
            windowNumber: number, ownerPID: pid, ownerName: name, title: title,
            layer: 0, alpha: 1, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }
}
