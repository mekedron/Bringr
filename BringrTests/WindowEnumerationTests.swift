import XCTest
@testable import Bringr

@MainActor
final class WindowEnumerationTests: XCTestCase {
    private let selfPID: pid_t = 1000

    // MARK: - AC1/AC3: returns apps with normal on-screen windows, drops the rest

    func testGroupsWindowsByAppPreservingFrontToBackOrder() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome"),
            raw(number: 2, pid: 20, name: "Ghostty"),
            raw(number: 3, pid: 10, name: "Chrome")
        ])
        let apps = WindowEnumerator(source: source).enumerate()

        XCTAssertEqual(apps.map(\.id), [AppID(pid: 10), AppID(pid: 20)])
        XCTAssertEqual(apps[0].name, "Chrome")
        XCTAssertEqual(apps[0].windows.map(\.id.token), [1, 3])
        XCTAssertEqual(apps[1].windows.map(\.id.token), [2])
    }

    func testExcludesNonNormalWindows() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome"),
            raw(number: 2, pid: 10, name: "Chrome", layer: 24),       // menu-bar layer
            raw(number: 3, pid: 10, name: "Chrome", alpha: 0),        // invisible helper
            raw(number: 4, pid: 10, name: "Chrome", width: 4, height: 4) // tiny helper
        ])
        let apps = WindowEnumerator(source: source).enumerate()

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].windows.map(\.id.token), [1])
    }

    func testAppWithOnlyNonNormalWindowsIsExcluded() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 30, name: "MenuBarApp", layer: 25), // status-item only
            raw(number: 2, pid: 30, name: "MenuBarApp", layer: 25),
            raw(number: 3, pid: 10, name: "Chrome")
        ])
        let apps = WindowEnumerator(source: source).enumerate()

        XCTAssertEqual(apps.map(\.id), [AppID(pid: 10)])
    }

    func testWindowsWithoutOwnerNameAreExcluded() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 40, name: ""),
            raw(number: 2, pid: 10, name: "Chrome")
        ])
        let apps = WindowEnumerator(source: source).enumerate()

        XCTAssertEqual(apps.map(\.id), [AppID(pid: 10)])
    }

    // MARK: - AC3: excludes Bringr itself

    func testExcludesOwnWindows() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: selfPID, name: "Bringr"),
            raw(number: 2, pid: 10, name: "Chrome")
        ])
        let apps = WindowEnumerator(source: source).enumerate()

        XCTAssertEqual(apps.map(\.id), [AppID(pid: 10)])
    }

    // MARK: - AC2: stable identifier, title, owning app

    func testStableIdentifierUsesWindowNumberAndCarriesOwningApp() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 4242, pid: 10, name: "Chrome")
        ])
        let apps = WindowEnumerator(source: source).enumerate()

        let window = apps[0].windows[0]
        XCTAssertEqual(window.id, WindowID(app: AppID(pid: 10), token: 4242))
        XCTAssertEqual(window.app, AppID(pid: 10))
    }

    func testUsesProvidedTitleTrimmedWhenPresent() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome", title: "  Inbox — Mail  ")
        ])
        let apps = WindowEnumerator(source: source).enumerate()

        XCTAssertEqual(apps[0].windows[0].title, "Inbox — Mail")
    }

    func testTitleFallsBackToOneBasedIndexWhenEmpty() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome", title: ""),
            raw(number: 2, pid: 10, name: "Chrome", title: "   ")
        ])
        let apps = WindowEnumerator(source: source).enumerate()

        XCTAssertEqual(apps[0].windows.map(\.title), ["Window 1", "Window 2"])
    }

    // MARK: - AC4: timing recorded; AC1: empty input

    func testLastDurationRecordedOnlyAfterEnumerate() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome")
        ])
        let enumerator = WindowEnumerator(source: source)

        XCTAssertNil(enumerator.lastDuration)
        _ = enumerator.enumerate()
        XCTAssertNotNil(enumerator.lastDuration)
        XCTAssertGreaterThanOrEqual(enumerator.lastDuration ?? -1, 0)
    }

    func testEmptySourceReturnsNoApps() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [])
        XCTAssertTrue(WindowEnumerator(source: source).enumerate().isEmpty)
    }

    // MARK: - Fixtures

    private func raw(
        number: Int,
        pid: pid_t,
        name: String,
        title: String = "",
        layer: Int = 0,
        alpha: Double = 1,
        width: CGFloat = 800,
        height: CGFloat = 600
    ) -> RawWindow {
        RawWindow(
            windowNumber: number,
            ownerPID: pid,
            ownerName: name,
            title: title,
            layer: layer,
            alpha: alpha,
            bounds: CGRect(x: 0, y: 0, width: width, height: height)
        )
    }
}

/// In-memory `WindowEnumerationSource` for tests: returns a fixed window list and
/// a configurable self-pid, with no live `CGWindowList` dependency.
@MainActor
final class FakeWindowEnumerationSource: WindowEnumerationSource {
    let selfPID: pid_t
    private let windows: [RawWindow]

    init(selfPID: pid_t, windows: [RawWindow]) {
        self.selfPID = selfPID
        self.windows = windows
    }

    func rawWindows() -> [RawWindow] { windows }
}
