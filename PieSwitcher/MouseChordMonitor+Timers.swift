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
    }

    func cancelHoldDelayTimer() {
        holdDelayTimer?.invalidate()
        holdDelayTimer = nil
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
        chordActive = true
        onChord()
    }
}
