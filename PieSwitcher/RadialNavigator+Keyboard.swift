import CoreGraphics
import Foundation

/// Keyboard-driven navigation over the navigator's live rings (Bringr-93j.71, Bringr-93j.72),
/// split out so `RadialNavigator.swift` stays within the file-length budget (mirroring
/// `RadialNavigator+Region.swift`).
///
/// Keyboard focus deliberately reuses the exact hover machinery — `updateHover` to move focus
/// *and* preview the target, `commit` to activate — so a focused window is isolated/previewed
/// identically to a hovered one (the spec's "focusing previews like hovering"), and there is no
/// second reveal/restore path to keep in sync. Mouse hover and keyboard focus therefore share
/// one highlighted region: whichever moved it last owns it, and the controller only tints the
/// result so keyboard focus reads distinctly. `expandedAppIndex`, `rings`, and `hasWindowSubWheel`
/// are all readable here, so these methods stay pure decisions over the live tree.
extension RadialNavigator {
    /// Move keyboard focus one step in `arrow`'s direction, previewing the new target. Left/
    /// Right move within the current ring (wrapping around the wheel); Up drills from an app
    /// into its windows and Down steps a window back to its parent app (Bringr-93j.72 reversed
    /// the vertical sense). The first arrow press while nothing is focused lands on the top app.
    ///
    /// In confirmation mode, once a number has focused a target awaiting confirmation, an arrow
    /// confirms it rather than moving (Bringr-93j.72): `pendingConfirmation` is set only by a
    /// number press in confirm mode, so its presence alone means an arrow should commit.
    func keyboardMove(_ arrow: KeyboardArrow) -> KeyboardNavOutcome {
        if pendingConfirmation != nil { return keyboardConfirm() }
        guard let appsRing = rings.first, !appsRing.nodes.isEmpty else { return .ignored }
        let appCount = appsRing.nodes.count

        switch hovered {
        case .none:
            updateHover(.slice(level: 0, index: 0))
            return .handled
        case .slice(level: 0, let index):
            switch arrow {
            case .left:
                updateHover(.slice(level: 0, index: KeyboardNavMath.wrap(index - 1, count: appCount)))
            case .right:
                updateHover(.slice(level: 0, index: KeyboardNavMath.wrap(index + 1, count: appCount)))
            case .up where hasWindowSubWheel:
                updateHover(.slice(level: 1, index: activeWindowIndex()))
            case .up, .down:
                break // Down at the top level, or Up into a window-less app, is a no-op.
            }
            return .handled
        case .slice(level: 1, let index):
            keyboardMoveOnWindows(arrow, index: index)
            return .handled
        case .slice:
            return .ignored
        }
    }

    private func keyboardMoveOnWindows(_ arrow: KeyboardArrow, index: Int) {
        guard rings.count > 1 else { return }
        let windowCount = rings[1].nodes.count
        switch arrow {
        case .left where windowCount > 0:
            updateHover(.slice(level: 1, index: KeyboardNavMath.wrap(index - 1, count: windowCount)))
        case .right where windowCount > 0:
            updateHover(.slice(level: 1, index: KeyboardNavMath.wrap(index + 1, count: windowCount)))
        case .down:
            updateHover(.slice(level: 0, index: expandedAppIndex ?? 0))
        case .left, .right, .up:
            break // Up has no deeper level in v1; left/right no-op on an empty ring.
        }
    }

    /// React to a pressed app/window number. The active context follows the focused level: at
    /// the apps level (or with nothing focused yet) the digit picks an app; once focus is on a
    /// window it picks a window — app numbers stay disabled until the focus steps back up
    /// (Bringr-93j.71). `requireConfirmation` turns an otherwise instant activation into a focus
    /// that is armed for confirmation (Bringr-93j.72).
    func keyboardNumber(
        _ digit: Int, requireConfirmation: Bool, autoCommitsApp: Bool = false
    ) -> KeyboardNavOutcome {
        guard let index = KeyboardNavMath.index(forDigit: digit), !rings.isEmpty else { return .ignored }
        if case .slice(level: 1, _) = hovered {
            return keyboardWindowNumber(at: index, requireConfirmation: requireConfirmation)
        }
        return keyboardAppNumber(
            at: index, requireConfirmation: requireConfirmation, autoCommitsApp: autoCommitsApp
        )
    }

    private func keyboardAppNumber(
        at index: Int, requireConfirmation: Bool, autoCommitsApp: Bool
    ) -> KeyboardNavOutcome {
        guard let appsRing = rings.first, index >= 0, index < appsRing.nodes.count else { return .handled }
        // Re-pressing the focused window-less app's own number confirms it (Bringr-93j.72).
        if requireConfirmation, pendingConfirmation == .slice(level: 0, index: index) {
            return commitOutcome(.slice(level: 0, index: index))
        }
        // Focus + preview the app: this expands it and resolves its live windows sub-wheel,
        // which is what tells us how many windows it has.
        updateHover(.slice(level: 0, index: index))
        let windowCount = hasWindowSubWheel ? rings[1].nodes.count : 0

        if windowCount == 0 {
            // No window to drill into: the app slice itself is the selection.
            return requireConfirmation ? arm(.slice(level: 0, index: index))
                                       : commitOutcome(.slice(level: 0, index: index))
        }
        if windowCount == 1 {
            // Exactly one window: it is the selection — open it now, or arm it for confirmation.
            if !requireConfirmation { return commitOutcome(.slice(level: 1, index: 0)) }
            updateHover(.slice(level: 1, index: 0))
            return arm(.slice(level: 1, index: 0))
        }
        // Several windows: drop in and preview the app's active window (Bringr-93j.73); the user can
        // still pick another by number/arrow. With "don't require a window choice" on, arm the app so
        // a release/confirm without a pick commits the app rather than reverting.
        updateHover(.slice(level: 1, index: activeWindowIndex()))
        if autoCommitsApp { pendingAppCommit = index }
        return .handled
    }

    private func keyboardWindowNumber(at index: Int, requireConfirmation: Bool) -> KeyboardNavOutcome {
        guard rings.count > 1, index >= 0, index < rings[1].nodes.count else { return .handled }
        guard requireConfirmation else { return commitOutcome(.slice(level: 1, index: index)) }
        // Re-pressing the focused window's own number confirms it; a different number focuses
        // and arms the new window (Bringr-93j.72).
        if pendingConfirmation == .slice(level: 1, index: index) {
            return commitOutcome(.slice(level: 1, index: index))
        }
        updateHover(.slice(level: 1, index: index))
        return arm(.slice(level: 1, index: index))
    }

    /// Arm `region` for confirmation: a number focused a terminal target in confirm mode, so an
    /// arrow, Space, Return, or re-pressing the same number then activates it (Bringr-93j.72).
    private func arm(_ region: HoverRegion) -> KeyboardNavOutcome {
        pendingConfirmation = region
        return .handled
    }

    /// Commit `region`, mapping a successful commit to `.committed` and a non-selectable region
    /// to a consumed `.handled` no-op (so the key never leaks to the app underneath).
    private func commitOutcome(_ region: HoverRegion) -> KeyboardNavOutcome {
        guard let result = commit(region) else { return .handled }
        return .committed(result)
    }

    /// Activate whatever is focused (Return / Space). When a number jumped to a multi-window app
    /// under "don't require a window choice", confirm commits that app instead of the previewed
    /// window (Bringr-93j.73). A dead-zone / nothing-focused confirm is consumed as a no-op rather
    /// than leaking to the app underneath.
    func keyboardConfirm() -> KeyboardNavOutcome {
        if let appIndex = pendingAppCommit { return commitOutcome(.slice(level: 0, index: appIndex)) }
        return commitOutcome(hovered)
    }

    /// The index, in the open windows sub-wheel, of the expanded app's active (front) window — so a
    /// keyboard drill-in lands focus on the active window rather than the first slice (Bringr-93j.73).
    /// Matches by stable window token, so it is correct regardless of the sub-wheel's sort order;
    /// falls back to 0 when the app's front window can't be matched (e.g. it isn't in the sub-wheel).
    private func activeWindowIndex() -> Int {
        guard rings.count > 1, let appID = expandedAppID,
              let front = windowControl.frontWindow(of: appID) else { return 0 }
        let index = rings[1].nodes.firstIndex {
            guard case .focusWindow(let id) = $0.action else { return false }
            return id == front
        }
        return index ?? 0
    }

    /// Escape: from a focused window, step back up to its parent app — restoring that window's
    /// preview and keeping the menu open; from the apps level, ask the controller to close.
    func keyboardEscape() -> KeyboardNavOutcome {
        if case .slice(level: 1, _) = hovered {
            updateHover(.slice(level: 0, index: expandedAppIndex ?? 0))
            return .handled
        }
        return .close
    }
}
