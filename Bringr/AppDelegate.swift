import AppKit

/// Owns app-lifetime services and runs launch-time bootstrap.
///
/// This is the home for launch work that has no clean SwiftUI hook in a
/// menu-bar-only app: today the Accessibility-permission bootstrap, later the
/// overlay pre-warm (US-006) and the global activation taps (US-007/US-008).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissions = PermissionsManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The host app is launched by `xcodebuild test` to inject the test
        // bundle; the prompt below would block that run and pop a system
        // permission dialog, so skip the bootstrap under XCTest.
        guard !AppDelegate.isRunningTests else { return }

        permissions.startMonitoring()
        if !permissions.isTrusted {
            permissions.requestAccess()
        }
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
