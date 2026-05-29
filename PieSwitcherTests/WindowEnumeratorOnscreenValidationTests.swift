import XCTest
@testable import PieSwitcher

/// On-screen phantom validation in all-screens mode (Bringr-93j.60): with no screen filter to
/// cull off-display phantom surfaces, an on-screen record is kept only if it is on a managed
/// Space. Off (the default), every on-screen record is trusted, so the screen-scoped and
/// all-Spaces-only paths are unchanged. In its own file (with a local `raw` helper) to keep
/// `WindowEnumeratorSpacesTests` within SwiftLint's file-length limit.
@MainActor
final class WindowEnumeratorOnscreenValidationTests: XCTestCase {
    private let selfPID: pid_t = 1000

    func testValidatingDropsOnscreenWindowWithNoManagedSpace() {
        // The bug: "all screens" listed phantom backing surfaces as windows. They are on-screen
        // (per CoreGraphics) yet on no managed Space, so validation drops them while the real,
        // managed window stays.
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome", isManagedWindow: true),
            raw(number: 2, pid: 10, name: "Chrome", isManagedWindow: false)
        ])

        let apps = WindowEnumerator(source: source).enumerate(validatesOnscreen: true)
        XCTAssertEqual(apps.map(\.name), ["Chrome"])
        XCTAssertEqual(apps[0].windows.map(\.id.token), [1])
    }

    func testNotValidatingTrustsEveryOnscreenWindow() {
        // The default (screen-scoped) path has a screen filter to cull off-display phantoms, so
        // it trusts on-screen records and never pays the managed-Space check — the unmanaged
        // record is kept here exactly as before the fix.
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome", isManagedWindow: true),
            raw(number: 2, pid: 10, name: "Chrome", isManagedWindow: false)
        ])

        let apps = WindowEnumerator(source: source).enumerate()
        XCTAssertEqual(apps[0].windows.map(\.id.token), [1, 2])
    }

    func testValidatingForwardsTheRequestToTheSource() {
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome", isManagedWindow: true)
        ])
        let enumerator = WindowEnumerator(source: source)

        _ = enumerator.enumerate()
        XCTAssertEqual(source.lastValidatingOnscreen, false)
        _ = enumerator.enumerate(validatesOnscreen: true)
        XCTAssertEqual(source.lastValidatingOnscreen, true)
    }

    func testAllScreensAndAllSpacesDropBothPhantomKinds() {
        // The full bead scenario: an on-screen phantom (no managed Space) and an off-screen
        // phantom (neither AX-backed nor managed) both vanish, while the real on-screen window
        // and a genuine other-Space window (AX-absent but managed) both stay.
        let source = FakeWindowEnumerationSource(
            selfPID: selfPID,
            windows: [raw(number: 1, pid: 10, name: "Chrome", isManagedWindow: true)],
            offscreenWindows: [
                raw(number: 1, pid: 10, name: "Chrome", isManagedWindow: true),               // real on-screen
                raw(number: 2, pid: 10, name: "Chrome", isManagedWindow: false),               // on-screen phantom
                raw(number: 3, pid: 10, name: "Chrome", isOnscreen: false,
                    isAXBacked: false, isManagedWindow: true),                                 // real other-Space
                raw(number: 4, pid: 10, name: "Chrome", isOnscreen: false, isAXBacked: false)  // off-screen phantom
            ]
        )

        let apps = WindowEnumerator(source: source)
            .enumerate(allSpaces: true, validatesOnscreen: true)
        XCTAssertEqual(apps.map(\.name), ["Chrome"])
        XCTAssertEqual(apps[0].windows.map(\.id.token).sorted(), [1, 3])
    }

    func testValidatedSummonScanServesUnvalidatedSubWheelFromCache() {
        // Bringr-93j.68: the apps ring is all-screens (validated), the windows sub-wheel screen-scoped
        // (unvalidated). A validated scan is a strict superset — validateOnscreen only *adds* a managed
        // stamp — so the sub-wheel reuses it rather than re-running the broadened source query (whose AX
        // classify hangs ~1–2 s when the reveal's `activate` is mid-foreground-transition). The reused
        // raw list still gets the unvalidated keep-rule, which trusts on-screen records, so the unmanaged
        // on-screen record the validated apps ring dropped reappears in the unvalidated sub-wheel.
        let source = FakeWindowEnumerationSource(
            selfPID: selfPID,
            windows: [raw(number: 1, pid: 10, name: "Chrome")],
            offscreenWindows: [
                raw(number: 1, pid: 10, name: "Chrome", isManagedWindow: true),
                raw(number: 2, pid: 10, name: "Chrome", isManagedWindow: false)
            ]
        )
        let enumerator = WindowEnumerator(source: source)

        let appsRing = enumerator.enumerate(allSpaces: true, validatesOnscreen: true, freshSummon: true)
        let subWheel = enumerator.enumerate(allSpaces: true, validatesOnscreen: false)

        XCTAssertEqual(source.broadenedCallCount, 1)                       // reused, not re-queried
        XCTAssertEqual(appsRing[0].windows.map(\.id.token), [1])           // validated drops the unmanaged one
        XCTAssertEqual(subWheel[0].windows.map(\.id.token).sorted(), [1, 2]) // unvalidated trusts both
    }

    func testUnvalidatedSummonScanDoesNotServeValidatedRead() {
        // The reverse is unsafe (an unvalidated cache lacks the managed stamps a validated keep-rule
        // needs — it would drop every on-screen window), so a validated read re-queries the source.
        let source = FakeWindowEnumerationSource(
            selfPID: selfPID,
            windows: [raw(number: 1, pid: 10, name: "Chrome")],
            offscreenWindows: [raw(number: 1, pid: 10, name: "Chrome", isManagedWindow: true)]
        )
        let enumerator = WindowEnumerator(source: source)

        _ = enumerator.enumerate(allSpaces: true, validatesOnscreen: false, freshSummon: true)
        _ = enumerator.enumerate(allSpaces: true, validatesOnscreen: true)
        XCTAssertEqual(source.broadenedCallCount, 2)
    }
}

/// Local fixture builder mirroring the one in `WindowEnumeratorSpacesTests`; `isManagedWindow`
/// is the signal this class exercises, so it is settable while everything else defaults to a
/// plain, real on-screen Dock-app window.
@MainActor
private func raw(
    number: Int, pid: pid_t, name: String,
    isOnscreen: Bool = true, isAXBacked: Bool = true, isManagedWindow: Bool = false
) -> RawWindow {
    RawWindow(
        windowNumber: number,
        ownerPID: pid,
        ownerName: name,
        title: "",
        layer: 0,
        alpha: 1,
        bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
        isOnscreen: isOnscreen,
        isAXBacked: isAXBacked,
        isManagedWindow: isManagedWindow
    )
}
