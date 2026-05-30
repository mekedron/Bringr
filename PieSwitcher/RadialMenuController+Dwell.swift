import AppKit
import SwiftUI

/// Hold-to-activate / dwell (Bringr-93j.105 / Bringr-93j.107), split into its own
/// extension so `RadialMenuController.swift` stays under the file-length budget
/// (mirroring `+Cursor` and `+Keyboard`). Resting the cursor on a slice for the
/// configured duration auto-commits it through the same click path the mouse and
/// keyboard already use.
///
/// The visual cue is a stroke around the dwelt slice's full perimeter, drawn by
/// `RadialMenuView` from the `(dwellRegion, dwellProgress)` published pair. Setting
/// `dwellProgress = 1.0` inside `withAnimation(.linear(duration:))` makes SwiftUI
/// animate the trim smoothly from empty to full over the dwell duration — the same
/// implicit-animation pattern `HoldProgressController` uses, no Display Link.
///
/// When `dwellConfig.duringDragOnly` is true (Bringr-93j.107 default), dwell is gated
/// to drag-and-drop: the timer only arms while the left mouse button is held (the
/// signal for a drag in progress), and a fire that would land outside a drag is
/// suppressed. This makes dwell safe to keep on without accidental auto-commits during
/// normal wheel use, while still serving the drag-then-switch flow (where the user
/// can't release to commit).
extension RadialMenuController {
    /// React to a hover update for dwell purposes. Called from `updateHover` after the
    /// navigator's hover state is in sync. Re-arming on a slice change resets the timer
    /// and the trim; staying on the same slice is a no-op so micro-mouse-motion within
    /// the slice doesn't reset progress (the PRD: "leaves that slice" — motion inside
    /// is fine). A `.none` (dead zone or off the wheel) clears the cue. In drag-only
    /// mode, a hover update with no mouse button held also clears (release-while-dwelling
    /// should not silently keep the arc growing toward a commit that won't happen).
    func applyDwell(for region: HoverRegion) {
        let config = dwellConfig
        guard config.enabled, case .slice = region else {
            cancelDwell()
            return
        }
        if config.duringDragOnly, !Self.isMouseDragInProgress() {
            cancelDwell()
            return
        }
        if dwellRegion == region { return }
        cancelDwell()
        dwellRegion = region
        // Snap progress to zero without animation first, so a same-frame re-arm doesn't
        // animate from the previous slice's stale fill.
        dwellProgress = 0
        let duration = config.duration
        guard duration > 0 else { return }
        withAnimation(.linear(duration: duration)) {
            dwellProgress = 1.0
        }
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dwellTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    /// Cancel any in-flight dwell, clearing the published cue. Safe to call when no dwell
    /// is armed — invalidate on `nil` and an empty-state assignment.
    func cancelDwell() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        if dwellRegion != .none {
            dwellRegion = .none
        }
        if dwellProgress != 0 {
            dwellProgress = 0
        }
    }

    /// The dwell duration elapsed — commit the slice the user was resting on through the
    /// same click path the mouse and keyboard already use, so the reveal-mode commit
    /// behaviour (raise to front, hide others, etc.) is identical for all three triggers.
    /// Cleared first so the cue disappears the instant the commit runs. In drag-only
    /// mode, a fire that lands outside a drag (the user released while the timer ran)
    /// is suppressed: the cue clears but no commit fires.
    func dwellTimerFired() {
        let region = dwellRegion
        let config = dwellConfig
        cancelDwell()
        guard isVisible, case .slice = region else { return }
        if config.duringDragOnly, !Self.isMouseDragInProgress() { return }
        // Route through the state machine just like a click: a click on a slice commits
        // in either interaction mode (hold-to-select gained click-to-activate in .91),
        // so dwell-commit lights up the same `select` outcome and the controller's
        // commit-and-restore path handles the rest.
        dispatchDwellCommit(region: region)
    }

    /// True if the left mouse button is currently pressed — the proxy for "a drag is in
    /// progress" in `duringDragOnly` mode. Native macOS DnD requires the left button to
    /// stay down for the duration of a drag (releasing drops the payload), so checking
    /// the button state is a faithful drag signal without needing a private API or
    /// being a drag destination ourselves. The check is cheap and intentionally static
    /// so the extension can reach it without crossing actor boundaries.
    static func isMouseDragInProgress() -> Bool {
        NSEvent.pressedMouseButtons & 0x1 != 0
    }

    /// Convenience for `dwellTimerFired` so the call site reads as a verb. Kept separate so
    /// future variations (e.g. window-only dwell) have one chokepoint to gate.
    private func dispatchDwellCommit(region: HoverRegion) {
        let outcome = machine.handle(.click(over: sliceTarget(region)))
        routeDwellOutcome(outcome, region: region)
    }

    /// Route a dwell-driven outcome through the same commit/cancel side effects the
    /// mouse and keyboard use. Mirrors the private `route` in the main controller; kept
    /// here so the extension doesn't need to escape `private` access barriers.
    private func routeDwellOutcome(_ outcome: InteractionOutcome, region: HoverRegion) {
        switch outcome {
        case .select:
            commitDwellSelection(region: region)
        case .cancel:
            dismissForDwell()
        case .none, .open:
            break
        }
    }

    /// Commit the dwell selection — exactly the body of the private `commitSelection`,
    /// re-stated here so it stays callable from the extension. The navigator's `commit`
    /// raises/focuses the target and restores the rest; `hideOverlay` takes the wheel
    /// down without re-running restore. A non-selectable region falls back to a
    /// cancel-restore so no reveal is left stranded.
    private func commitDwellSelection(region: HoverRegion) {
        if navigator.commit(region) == nil {
            dismissForDwell()
        } else {
            hideOverlay()
        }
    }

    /// The dwell's cancel-and-restore path, mirroring the private `dismiss` in the main
    /// controller. Restores any hidden app/window then takes the overlay down.
    private func dismissForDwell() {
        navigator.close()
        hideOverlay()
    }
}
