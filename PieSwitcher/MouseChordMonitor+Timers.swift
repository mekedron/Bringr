import AppKit
import CoreGraphics
import Foundation

// MARK: - Timers and event replay

/// `MouseChordMonitor`'s scheduled work — the pursuit timeout, the hold delay, and the
/// replay-buffer mechanism — lives here so the core class body stays under the
/// `type_body_length` cap. The split is purely organisational: the methods are accessed
/// only from the monitor itself, so they're internal (not private) only to clear the
/// file-scope visibility barrier.
extension MouseChordMonitor {
    /// Re-inject every buffered press, in order, tagged so the tap lets them through.
    /// Posting from inside the callback keeps the original ordering, so the app sees a
    /// clean press/release rather than an out-of-order pair.
    func replayHeldEvents() {
        cancelPursuitTimer()
        let events = heldEvents
        heldEvents.removeAll()
        pressLocation = nil
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.replaySentinel)
            event.post(tap: .cgSessionEventTap)
        }
    }

    func schedulePursuitTimer() {
        cancelPursuitTimer()
        let timer = Timer(timeInterval: detector.pursuitTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.pursuitTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pursuitTimer = timer
    }

    func cancelPursuitTimer() {
        pursuitTimer?.invalidate()
        pursuitTimer = nil
    }

    func pursuitTimerFired() {
        if detector.handleTimeout(at: ProcessInfo.processInfo.systemUptime) {
            replayHeldEvents()
        }
    }

    func scheduleHoldDelayTimer(delay: TimeInterval) {
        cancelHoldDelayTimer()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.holdDelayTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdDelayTimer = timer
        // Fire the progress-indicator (Bringr-93j.103) at the same delay the timer uses, so
        // the cursor circle fills in lock-step with the hold the user is performing.
        onProgressStart(delay)
    }

    func cancelHoldDelayTimer() {
        let wasArmed = holdDelayTimer != nil
        holdDelayTimer?.invalidate()
        holdDelayTimer = nil
        if wasArmed { onProgressEnd() }
    }

    /// The user-visible hold delay elapsed. If the same method is still matched (the user
    /// kept holding), promote the detector to chord state, discard the buffered events
    /// (their button actions never reach the focused app), and fire the summon. If the
    /// match disappeared (a button released before the delay completed), do nothing — the
    /// detector already replayed or kept the buffer; the `pendingMatch` gate avoids a stale
    /// fire from a re-armed timer.
    func holdDelayTimerFired() {
        cancelHoldDelayTimer()
        guard let matched = detector.matchedMethod, matched == pendingMatch else { return }
        pendingMatch = nil
        detector.chordSummoned()
        heldEvents.removeAll()
        pressLocation = nil
        chordActive = true
        onChord()
    }

    // MARK: - Move-threshold drag handling (Bringr-93j.103)

    /// A drag with a button held while we're still pursuing is treated as a drag, not a
    /// chord — but only past the configurable move threshold. Below threshold the drag is
    /// buffered alongside the press so a steady-finger micro-twitch can't end the pursuit
    /// (Bringr-93j.103); above threshold the buffer replays so the focused app sees the
    /// drag start without a stall (Bringr-93j.94 / Bringr-93j.96).
    func handleDrag(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard detector.isPursuing else { return Unmanaged.passUnretained(event) }
        let threshold = moveThresholdProvider()
        if let pressLocation, exceedsThreshold(current: event.location, origin: pressLocation, threshold: threshold) {
            return abandonPursuit(appending: event, lock: lockProvider())
        }
        heldEvents.append(event)
        return nil
    }

    /// Squared-distance comparison so we never need the costly sqrt — exact for our
    /// "is the cursor more than N points away" question.
    private func exceedsThreshold(current: CGPoint, origin: CGPoint, threshold: CGFloat) -> Bool {
        let dx = current.x - origin.x
        let dy = current.y - origin.y
        return (dx * dx + dy * dy) > (threshold * threshold)
    }

    /// Tear down the in-progress pursuit because the threshold was crossed. With Lock OFF
    /// the buffered events replay so the focused app sees a clean press/drag; with Lock ON
    /// the buffer is dropped entirely so the activation button stays locked for the whole
    /// gesture (Bringr-93j.103).
    private func abandonPursuit(appending event: CGEvent, lock: Bool) -> Unmanaged<CGEvent>? {
        _ = detector.motionDetected()
        cancelHoldDelayTimer()
        pendingMatch = nil
        if lock {
            heldEvents.removeAll()
            pressLocation = nil
            return nil
        }
        heldEvents.append(event)
        replayHeldEvents()
        return nil
    }
}
