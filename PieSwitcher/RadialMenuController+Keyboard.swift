import AppKit

/// Keyboard-navigation entry point for the controller (Bringr-93j.71), split out so
/// `RadialMenuController.swift` stays within the file-length budget (mirroring
/// `RadialMenuController+Cursor.swift`). The live `KeyboardNavMonitor` calls in here for each
/// key while the menu is open; the controller routes the key to the navigator's keyboard
/// decision logic and performs the resulting side effect, reusing the same commit/cancel paths
/// the mouse uses.
extension RadialMenuController {
    /// Whether keyboard navigation should handle keys right now: the wheel is on screen and the
    /// per-summon resolved settings have it enabled. The monitor consults this before consuming
    /// any key, so when the feature is off keys pass straight through.
    var acceptsKeyboardNav: Bool {
        isVisible && keyboardConfig.isEnabled
    }

    /// Handle one navigation key. Returns `true` when the key was consumed (so the monitor stops
    /// it reaching the app underneath), `false` to let it pass through — including keys for a
    /// sub-mode the user disabled.
    @discardableResult
    func handleKeyboardNavKey(_ key: KeyboardNavKey) -> Bool {
        guard acceptsKeyboardNav, let outcome = keyboardOutcome(for: key) else { return false }
        switch outcome {
        case .ignored:
            return false
        case .handled:
            highlightSource = .keyboard
            syncFromNavigator()
            return true
        case .committed:
            // The navigator already raised/focused the target and restored the rest, like the
            // mouse commit path; just mark the machine closed and take the overlay down.
            machine.markClosed()
            hideOverlay()
            return true
        case .close:
            escapePressed() // top-level Escape cancels and restores, in either mode (US-015).
            return true
        }
    }

    /// Map a key to the navigator's decision, gating each key on the sub-mode that owns it:
    /// Escape always works while open; arrows need arrow mode; digits need number mode; Return
    /// works in either (it commits arrow focus and confirms number focus). An unsupported key
    /// closes the wheel when that option is on, else passes through. `nil` means "not for keyboard
    /// nav" — pass it through.
    private func keyboardOutcome(for key: KeyboardNavKey) -> KeyboardNavOutcome? {
        switch key {
        case .escape:
            return navigator.keyboardEscape()
        case .arrow(let arrow):
            guard keyboardConfig.arrowsEnabled else { return nil }
            return navigator.keyboardMove(arrow)
        case .digit(let digit):
            guard keyboardConfig.numbersEnabled else { return nil }
            return navigator.keyboardNumber(
                digit, requireConfirmation: keyboardConfig.requiresConfirmation,
                autoCommitsApp: keyboardConfig.commitsAppWithoutWindowChoice
            )
        case .confirm:
            guard keyboardConfig.arrowsEnabled || keyboardConfig.numbersEnabled else { return nil }
            return navigator.keyboardConfirm()
        case .unsupported:
            // A key the wheel doesn't use: close it (a full cancel/restore via `escapePressed`)
            // when "close on any other key" is on, otherwise let it pass through (Bringr-93j.73).
            return keyboardConfig.closesOnUnsupportedKey ? .close : nil
        }
    }

    /// Commit the app a numeric jump landed on but never picked a window in, when "don't require a
    /// window choice" is on (Bringr-93j.73): in hold-to-select, releasing the trigger over that
    /// auto-previewed multi-window app activates the app (and its active window) instead of
    /// cancelling on the dead-zone cursor. Returns whether it committed, so the normal release
    /// handling runs only when it didn't.
    func commitPendingAppOnRelease() -> Bool {
        guard machine.mode == .holdToSelect, let appIndex = navigator.pendingAppCommit,
              navigator.commit(.slice(level: 0, index: appIndex)) != nil else { return false }
        machine.markClosed()
        hideOverlay()
        return true
    }
}
