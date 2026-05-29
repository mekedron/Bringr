import AppKit
import XCTest
@testable import PieSwitcher

@MainActor
final class DockIconManagerTests: XCTestCase {
    func testOpeningFirstWindowShowsDockIcon() {
        var policies: [NSApplication.ActivationPolicy] = []
        let manager = DockIconManager(setPolicy: { policies.append($0) })

        manager.windowOpened()

        XCTAssertEqual(policies, [.regular])
        XCTAssertEqual(manager.openWindowCount, 1)
    }

    func testClosingLastWindowHidesDockIcon() {
        var policies: [NSApplication.ActivationPolicy] = []
        let manager = DockIconManager(setPolicy: { policies.append($0) })

        manager.windowOpened()
        manager.windowClosed()

        XCTAssertEqual(policies, [.regular, .accessory])
        XCTAssertEqual(manager.openWindowCount, 0)
    }

    func testSecondWindowDoesNotReassertRegularPolicy() {
        var policies: [NSApplication.ActivationPolicy] = []
        let manager = DockIconManager(setPolicy: { policies.append($0) })

        manager.windowOpened()
        manager.windowOpened()

        // Only the 0->1 edge flips the policy; a second window must not re-apply it.
        XCTAssertEqual(policies, [.regular])
        XCTAssertEqual(manager.openWindowCount, 2)
    }

    func testClosingOneOfTwoWindowsKeepsDockIcon() {
        var policies: [NSApplication.ActivationPolicy] = []
        let manager = DockIconManager(setPolicy: { policies.append($0) })

        manager.windowOpened()
        manager.windowOpened()
        manager.windowClosed()

        // The icon hides only on the 1->0 edge, so a still-open window keeps it.
        XCTAssertEqual(policies, [.regular])
        XCTAssertEqual(manager.openWindowCount, 1)
    }

    func testReopeningAfterCloseShowsDockIconAgain() {
        var policies: [NSApplication.ActivationPolicy] = []
        let manager = DockIconManager(setPolicy: { policies.append($0) })

        manager.windowOpened()
        manager.windowClosed()
        manager.windowOpened()

        XCTAssertEqual(policies, [.regular, .accessory, .regular])
        XCTAssertEqual(manager.openWindowCount, 1)
    }

    func testUnbalancedCloseIsIgnored() {
        var policies: [NSApplication.ActivationPolicy] = []
        let manager = DockIconManager(setPolicy: { policies.append($0) })

        // A stray disappear with nothing open must not underflow the count or
        // spuriously toggle the policy.
        manager.windowClosed()

        XCTAssertEqual(policies, [])
        XCTAssertEqual(manager.openWindowCount, 0)
    }
}
