import AppKit
import ApplicationServices
import Foundation

/// Coarse Accessibility-permission state, mapped to user-facing copy.
///
/// US-002 only concerns the Accessibility API (`AXIsProcessTrusted`), which
/// gates window enumeration/control (US-003/US-004) and the global event tap
/// (US-007). Input-Monitoring is requested implicitly when the event tap is
/// installed and is handled by that later story.
enum PermissionStatus: Equatable {
    case granted
    case denied

    var isGranted: Bool { self == .granted }

    /// Short headline shown next to the status indicator.
    var title: String {
        switch self {
        case .granted: return "Accessibility access granted"
        case .denied: return "Accessibility access required"
        }
    }

    /// Longer explanation of what the state means for the user.
    var detail: String {
        switch self {
        case .granted:
            return "Bringr can read and control windows and observe global input."
        case .denied:
            return "Bringr needs Accessibility access to enumerate windows, switch "
                + "between them, and detect its activation gestures. Grant access in "
                + "System Settings, then re-check."
        }
    }

    /// SF Symbol used by the status indicator.
    var symbolName: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        }
    }
}

/// Observes and requests the Accessibility permission Bringr needs.
///
/// The live system calls are injected so the logic can be unit-tested with
/// fixtures — no real permission state and no system prompt during tests.
@MainActor
final class PermissionsManager: ObservableObject {
    /// Whether the process is currently trusted for the Accessibility API.
    @Published private(set) var isTrusted: Bool

    private let probe: () -> Bool
    private let promptForAccess: () -> Void
    private let openSettings: () -> Void

    private var pollTimer: Timer?
    private var isMonitoring = false

    init(
        probe: @escaping () -> Bool = PermissionsManager.systemIsTrusted,
        promptForAccess: @escaping () -> Void = PermissionsManager.systemPromptForAccess,
        openSettings: @escaping () -> Void = PermissionsManager.systemOpenSettings
    ) {
        self.probe = probe
        self.promptForAccess = promptForAccess
        self.openSettings = openSettings
        self.isTrusted = probe()
    }

    /// Current permission state mapped to user-facing copy.
    var status: PermissionStatus { isTrusted ? .granted : .denied }

    /// Re-reads the live trust state and publishes any change.
    func recheck() {
        let current = probe()
        if current != isTrusted {
            isTrusted = current
        }
    }

    /// Shows the system Accessibility prompt, which links to System Settings.
    func requestAccess() {
        promptForAccess()
    }

    /// Opens the Accessibility pane of System Settings directly.
    func openAccessibilitySettings() {
        openSettings()
    }

    /// Begins watching for permission changes so they are picked up without a
    /// manual relaunch. Safe to call repeatedly.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(permissionMayHaveChanged),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Stops watching for permission changes.
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private nonisolated func permissionMayHaveChanged() {
        Task { @MainActor [weak self] in self?.recheck() }
    }

    // MARK: - Live system implementations

    nonisolated static func systemIsTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    nonisolated static func systemPromptForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    nonisolated static func systemOpenSettings() {
        let path = "x-apple.systempreferences:com.apple.preference.security"
            + "?Privacy_Accessibility"
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
