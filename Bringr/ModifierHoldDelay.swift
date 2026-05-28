import Foundation

// MARK: - Persisted hold delay

/// How long the activation modifier key(s) must be held before the menu opens
/// (Bringr-93j.58). A short hold means a quick *tap* of a modifier that does
/// something else — e.g. Fn also switches the input language — won't summon the
/// wheel; only an intentional hold past the delay does.
///
/// The value is persisted in **milliseconds** so the Preferences slider and numeric
/// field bind to it directly with no conversion; `current(from:)` returns it in
/// seconds, ready to feed the press-delay timer. Read fresh per press, like the other
/// settings, so a Preferences change applies on the next hold without a relaunch.
enum ActivationHoldDelay {
    /// `UserDefaults` key backing the persisted delay. Single source of truth shared by
    /// the Preferences `@AppStorage` and the readers so they cannot drift.
    static let defaultsKey = "activation.holdDelayMilliseconds"

    /// 100 ms by default: long enough that a quick Fn tap (language switch) doesn't
    /// summon, short enough that a deliberate hold still feels immediate.
    static let defaultMilliseconds: Double = 100

    /// The slider/field bounds, in milliseconds. 0 = no delay (summon on the rising edge,
    /// preserving the pre-93j.58 behaviour); 1000 ms is a generous upper bound.
    static let millisecondRange: ClosedRange<Double> = 0...1000

    /// The persisted delay in **seconds**, clamped to the range, ready for a timer.
    static func current(from defaults: UserDefaults = .standard) -> TimeInterval {
        milliseconds(from: defaults) / 1000
    }

    /// The persisted delay in milliseconds (the stored unit), clamped to the range. An
    /// absent key yields the default — `double(forKey:)` alone returns 0 for a missing
    /// key, which would silently mean "no delay", so the presence check guards that.
    static func milliseconds(from defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: defaultsKey) != nil else { return defaultMilliseconds }
        return clampMilliseconds(defaults.double(forKey: defaultsKey))
    }

    /// Clamp a raw millisecond value into `millisecondRange`, so a stray stored or typed
    /// value never produces an absurd delay.
    static func clampMilliseconds(_ value: Double) -> Double {
        min(max(value, millisecondRange.lowerBound), millisecondRange.upperBound)
    }
}

// MARK: - Delay gate (pure)

/// Bridges the press/release edges from `ModifierHoldDetector` to a delayed summon
/// (Bringr-93j.58). It does not own a timer — it only tracks where a hold is in its
/// life cycle so the live monitor can decide, race-free, whether a fired timer should
/// deliver the press and whether a release should cancel a still-pending one or
/// propagate as a real release.
///
/// Pure and value-typed, so the whole decision is unit-tested without a live timer.
/// The state guard in `delayElapsed()` is what makes the timer safe: a release that
/// arrives first flips the gate back to idle, so a timer that fires afterwards (its
/// callback already queued) sees `idle` and declines to deliver.
struct ModifierHoldDelayGate {
    private enum State { case idle, pending, pressed }
    private var state: State = .idle

    /// The detector's rising edge. Returns whether the monitor should arm a delay timer;
    /// only an idle gate arms, so a stray press while already pending/pressed is ignored.
    mutating func press() -> Bool {
        guard state == .idle else { return false }
        state = .pending
        return true
    }

    /// The delay timer fired. Returns whether the press should be delivered now — true
    /// only if the hold survived the whole delay (still pending). A stale fire after a
    /// cancelling release returns false.
    mutating func delayElapsed() -> Bool {
        guard state == .pending else { return false }
        state = .pressed
        return true
    }

    /// What the monitor should do with the detector's falling edge.
    enum Release: Equatable {
        /// The hold ended before the delay elapsed — cancel the timer, summon nothing.
        case cancelPendingPress
        /// The press was already delivered — propagate the release (commit / dismiss).
        case propagateRelease
        /// Nothing was in flight.
        case ignore
    }

    /// The detector's falling edge.
    mutating func release() -> Release {
        switch state {
        case .pending:
            state = .idle
            return .cancelPendingPress
        case .pressed:
            state = .idle
            return .propagateRelease
        case .idle:
            return .ignore
        }
    }

    /// Drop all in-flight state when the monitor (re)starts or stops. The monitor also
    /// cancels its timer, so a stale hold never resolves into a new session.
    mutating func reset() { state = .idle }
}
