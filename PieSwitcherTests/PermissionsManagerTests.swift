import XCTest
@testable import PieSwitcher

@MainActor
final class PermissionsManagerTests: XCTestCase {
    func testStatusReflectsGrantedProbe() {
        let manager = PermissionsManager(probe: { true })
        XCTAssertTrue(manager.isTrusted)
        XCTAssertEqual(manager.status, .granted)
        XCTAssertTrue(manager.status.isGranted)
    }

    func testStatusReflectsDeniedProbe() {
        let manager = PermissionsManager(probe: { false })
        XCTAssertFalse(manager.isTrusted)
        XCTAssertEqual(manager.status, .denied)
        XCTAssertFalse(manager.status.isGranted)
    }

    func testRecheckPicksUpPermissionChange() {
        var granted = false
        let manager = PermissionsManager(probe: { granted })
        XCTAssertFalse(manager.isTrusted)

        granted = true
        manager.recheck()
        XCTAssertTrue(manager.isTrusted)

        granted = false
        manager.recheck()
        XCTAssertFalse(manager.isTrusted)
    }

    func testRequestAccessInvokesPrompt() {
        var prompted = false
        let manager = PermissionsManager(probe: { false }, promptForAccess: { prompted = true })
        manager.requestAccess()
        XCTAssertTrue(prompted)
    }

    func testOpenAccessibilitySettingsInvokesHandler() {
        var opened = false
        let manager = PermissionsManager(probe: { false }, openSettings: { opened = true })
        manager.openAccessibilitySettings()
        XCTAssertTrue(opened)
    }

    func testDeniedStatusSurfacesActionableMessage() {
        XCTAssertFalse(PermissionStatus.denied.title.isEmpty)
        XCTAssertFalse(PermissionStatus.denied.detail.isEmpty)
    }

    func testGrantedAndDeniedUseDistinctSymbols() {
        XCTAssertNotEqual(
            PermissionStatus.granted.symbolName,
            PermissionStatus.denied.symbolName
        )
    }
}
