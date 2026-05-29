import XCTest
@testable import PieSwitcher

/// `.recentlyUsed` sort: each summon reflects the live front-to-back z-order
/// (Bringr-93j.85). The earlier persisted-MRU layer (Bringr-93j.46) was removed
/// because it only ever advanced the live front, so an app the user raised between
/// summons (Cmd-Tab, Dock click, external focus) stayed stuck where the prior summon
/// left it — perceived as the sort being broken. Its own file (not in
/// `WindowEnumerationTests`) so the host suite stays under SwiftLint's length cap.
@MainActor
final class WindowEnumeratorRecentlyUsedTests: XCTestCase {
    private let selfPID: pid_t = 1000

    func testAppsReflectNewLiveOrderAcrossSummons() {
        let enumerator = WindowEnumerator(
            source: FakeWindowEnumerationSource(selfPID: selfPID, windows: [
                raw(number: 1, pid: 20, name: "Ghostty"),
                raw(number: 2, pid: 10, name: "Chrome"),
                raw(number: 3, pid: 30, name: "Mail")
            ]),
            appOrder: { .recentlyUsed }, windowOrder: { .recentlyUsed }
        )
        _ = enumerator.enumerate(freshSummon: true)

        // Same front (Ghostty), but Mail now ranks above Chrome — the user used Mail
        // between summons.
        let next = WindowEnumerator(
            source: FakeWindowEnumerationSource(selfPID: selfPID, windows: [
                raw(number: 1, pid: 20, name: "Ghostty"),
                raw(number: 3, pid: 30, name: "Mail"),
                raw(number: 2, pid: 10, name: "Chrome")
            ]),
            appOrder: { .recentlyUsed }, windowOrder: { .recentlyUsed }
        ).enumerate(freshSummon: true)

        XCTAssertEqual(next.map(\.name), ["Ghostty", "Mail", "Chrome"])
    }

    func testWindowsReflectNewLiveOrderAcrossSummons() {
        _ = WindowEnumerator(
            source: FakeWindowEnumerationSource(selfPID: selfPID, windows: [
                raw(number: 1, pid: 10, name: "Chrome"),
                raw(number: 2, pid: 10, name: "Chrome"),
                raw(number: 3, pid: 10, name: "Chrome")
            ]),
            appOrder: { .recentlyUsed }, windowOrder: { .recentlyUsed }
        ).enumerate(freshSummon: true)

        // User raised window 3 between summons; the new summon shows that order.
        let next = WindowEnumerator(
            source: FakeWindowEnumerationSource(selfPID: selfPID, windows: [
                raw(number: 3, pid: 10, name: "Chrome"),
                raw(number: 1, pid: 10, name: "Chrome"),
                raw(number: 2, pid: 10, name: "Chrome")
            ]),
            appOrder: { .recentlyUsed }, windowOrder: { .recentlyUsed }
        ).enumerate(freshSummon: true)

        XCTAssertEqual(next[0].windows.map(\.id.token), [3, 1, 2])
    }

    // MARK: - Fixtures

    private func raw(number: Int, pid: pid_t, name: String) -> RawWindow {
        RawWindow(
            windowNumber: number, ownerPID: pid, ownerName: name, title: "",
            layer: 0, alpha: 1, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }
}
