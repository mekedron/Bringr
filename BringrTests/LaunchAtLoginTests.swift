import XCTest
@testable import Bringr

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testInitialStateReflectsEnabledProbe() {
        let manager = LaunchAtLoginManager(probe: { true })
        XCTAssertTrue(manager.isEnabled)
    }

    func testInitialStateReflectsDisabledProbe() {
        let manager = LaunchAtLoginManager(probe: { false })
        XCTAssertFalse(manager.isEnabled)
    }

    func testEnableRegistersAndReflectsNewStatus() {
        var registered = false
        let manager = LaunchAtLoginManager(
            probe: { registered },
            register: { registered = true },
            unregister: { registered = false }
        )
        XCTAssertFalse(manager.isEnabled)

        manager.setEnabled(true)
        XCTAssertTrue(registered)
        XCTAssertTrue(manager.isEnabled)
    }

    func testDisableUnregistersAndReflectsStatus() {
        var registered = true
        let manager = LaunchAtLoginManager(
            probe: { registered },
            register: { registered = true },
            unregister: { registered = false }
        )
        XCTAssertTrue(manager.isEnabled)

        manager.setEnabled(false)
        XCTAssertFalse(registered)
        XCTAssertFalse(manager.isEnabled)
    }

    func testEnableThenDisableTogglesStatus() {
        var registered = false
        let manager = LaunchAtLoginManager(
            probe: { registered },
            register: { registered = true },
            unregister: { registered = false }
        )

        manager.setEnabled(true)
        XCTAssertTrue(manager.isEnabled)
        manager.setEnabled(false)
        XCTAssertFalse(manager.isEnabled)
    }

    func testRegisterFailureLeavesStateConsistentWithSystem() {
        // The system call throws and the login item never actually enables, so the
        // toggle must fall back to "off" rather than the requested "on".
        var registered = false
        let manager = LaunchAtLoginManager(
            probe: { registered },
            register: { throw CocoaError(.fileWriteUnknown) },
            unregister: { registered = false }
        )

        manager.setEnabled(true)
        XCTAssertFalse(manager.isEnabled)
    }

    func testRefreshPicksUpExternalChange() {
        var enabled = false
        let manager = LaunchAtLoginManager(probe: { enabled })
        XCTAssertFalse(manager.isEnabled)

        enabled = true
        manager.refresh()
        XCTAssertTrue(manager.isEnabled)

        enabled = false
        manager.refresh()
        XCTAssertFalse(manager.isEnabled)
    }
}
