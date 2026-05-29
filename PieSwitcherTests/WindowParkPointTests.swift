import CoreGraphics
import XCTest
@testable import PieSwitcher

/// The nominal off-screen park sentinel is still far off every display on X — the
/// in-memory fake and tests use it as "this window is parked". The live park's real
/// geometry lives in `WindowParkGeometryTests`.
@MainActor
final class WindowParkPointTests: XCTestCase {
    func testParkSentinelIsFarOffScreenOnX() {
        XCTAssertGreaterThan(WindowController.offScreenPoint.x, 10_000,
                             "X is far off every display, so the window fully hides")
    }
}

/// Bringr-93j.81: the window-level hide-others reveal parks an app's other windows
/// off-screen by moving them. macOS won't let a title bar leave every display, so it
/// slides a parked window back onto the *extreme* display in the park direction and
/// clamps its height to that display's height. Parking far-right re-homed a tall window
/// onto the rightmost (laptop — shorter, vertically offset) display and shrank it, and
/// the clamp never fully restored (~250px lost per hover). `WindowParkGeometry` instead
/// parks toward the side whose extreme display is *tallest*, so a tall window lands on a
/// display at least as tall as itself and is never clamped. These tests lock that in.
@MainActor
final class WindowParkGeometryTests: XCTestCase {
    /// The reporter's real layout (ground-truthed): a tall main display at the origin and
    /// a shorter laptop to its right, offset down. The tall display is the left extreme,
    /// so a window must park LEFT — never right onto the shorter laptop (the bug).
    func testParksTowardTallLeftExtreme() {
        let screens = [
            CGRect(x: 0, y: 0, width: 3008, height: 1692),      // tall main, leftmost
            CGRect(x: 3008, y: 252, width: 1728, height: 1117)  // shorter laptop, rightmost
        ]
        let parkedX = WindowParkGeometry.parkedX(screenFrames: screens)
        XCTAssertEqual(parkedX, 0 - WindowParkGeometry.offScreenInset)
        XCTAssertLessThan(parkedX, screens.map(\.minX).min()!, "parked off the left of every display")
    }

    /// Mirror image: the tall display is the right extreme, so the window must park RIGHT
    /// so it re-homes onto the tall display, not the shorter one on the left.
    func testParksTowardTallRightExtreme() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1728, height: 1117),      // shorter, leftmost
            CGRect(x: 1728, y: 0, width: 3008, height: 1692)    // tall, rightmost
        ]
        let parkedX = WindowParkGeometry.parkedX(screenFrames: screens)
        XCTAssertEqual(parkedX, 4736 + WindowParkGeometry.offScreenInset)
        XCTAssertGreaterThan(parkedX, screens.map(\.maxX).max()!, "parked off the right of every display")
    }

    /// One display: either direction re-homes the window onto that same display (tall
    /// enough for a window that already fit there), so the height is never clamped.
    func testSingleDisplayParksOffThatDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let parkedX = WindowParkGeometry.parkedX(screenFrames: [screen])
        XCTAssertEqual(parkedX, 0 - WindowParkGeometry.offScreenInset)
    }

    /// Equal-height extremes resolve deterministically to the left so the choice is stable.
    func testEqualHeightExtremesParkLeftDeterministically() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        ]
        XCTAssertEqual(WindowParkGeometry.parkedX(screenFrames: screens),
                       0 - WindowParkGeometry.offScreenInset)
    }

    /// No displays reported: fall back to a far value rather than trapping.
    func testNoDisplaysFallsBackToFarValue() {
        XCTAssertEqual(WindowParkGeometry.parkedX(screenFrames: []), WindowParkGeometry.offScreenInset)
    }

    /// The invariant behind the fix: whichever side is chosen, its extreme display is the
    /// taller of the two extremes — so a window never re-homes onto the shorter display.
    func testChosenSideAlwaysHasTheTallerExtreme() {
        let layouts: [[CGRect]] = [
            [CGRect(x: 0, y: 0, width: 3008, height: 1692), CGRect(x: 3008, y: 252, width: 1728, height: 1117)],
            [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: 1728, y: 0, width: 3008, height: 1692)],
            [CGRect(x: -1440, y: 0, width: 1440, height: 900), CGRect(x: 0, y: 0, width: 2560, height: 1440)]
        ]
        for screens in layouts {
            let parkedX = WindowParkGeometry.parkedX(screenFrames: screens)
            let leftMost = screens.min { $0.minX < $1.minX }!
            let rightMost = screens.max { $0.maxX < $1.maxX }!
            let parkedLeft = parkedX < leftMost.minX
            let landingHeight = parkedLeft ? leftMost.height : rightMost.height
            XCTAssertEqual(landingHeight, max(leftMost.height, rightMost.height),
                           "parks toward the taller extreme so a tall window is never clamped")
        }
    }
}
