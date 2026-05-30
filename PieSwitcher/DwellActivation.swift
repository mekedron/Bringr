import Foundation

/// Hold-to-activate / dwell (Bringr-93j.105): when the cursor rests on a slice for a
/// configurable duration, that slice is auto-committed — no click or release needed.
/// A bundled value for all three knobs (`enabled` + `duration` + `duringDragOnly`) is
/// what `RadialMenuController` resolves once per summon, mirroring how the other
/// settings are read fresh so a Preferences change applies on the next open without a
/// relaunch.
///
/// Stored as a caseless `enum` namespace with explicit `defaultsKey` / `default*` /
/// presence-checked readers, matching the project's persisted-setting convention
/// (without the presence check, `bool(forKey:)` returns `false` for an absent key and
/// would silently flip the default to OFF; `double(forKey:)` returns 0 and would yield
/// a degenerate instant dwell).
///
/// Visual cue: a progress stroke around the slice's full perimeter (outer arc, both
/// radial sides, inner arc), parallel to the cursor-centred ring in Bringr-93j.103 —
/// same fill pattern, different anchor (the slice you're aiming at, not the cursor
/// that's aiming).
enum DwellActivation {
    /// `UserDefaults` key for the on/off switch.
    static let enabledDefaultsKey = "dwellActivation.enabled"
    /// `UserDefaults` key for the dwell duration, in milliseconds (the stored unit so
    /// the Preferences slider binds directly with no conversion).
    static let durationDefaultsKey = "dwellActivation.durationMilliseconds"
    /// `UserDefaults` key for the "only fire dwell during drag-and-drop" gate
    /// (Bringr-93j.107). When true, dwell-commit only triggers while the user is
    /// holding the left mouse button (i.e. performing a drag) — outside of a drag the
    /// wheel commits only on release/click, so the dwell never auto-fires unexpectedly
    /// during normal use. The drag-then-switch workflow (e.g. dragging a file into a
    /// target app via the wheel) is the one case where the user can't release the
    /// mouse to commit; dwell unblocks it.
    static let duringDragOnlyDefaultsKey = "dwellActivation.duringDragOnly"

    /// On by default — dwell is the third commit path alongside release (hold-to-select)
    /// and click (click-to-stay), most users want it; the user opts out with the checkbox.
    static let defaultEnabled = true
    /// 2500 ms (2.5 s) by default — long enough that gliding past a slice doesn't trip it
    /// accidentally, short enough that a deliberate rest still feels like activation.
    static let defaultDurationMilliseconds: Double = 2500
    /// On by default (Bringr-93j.107): restricts dwell to drag-and-drop so a normal use
    /// of the wheel never auto-commits unexpectedly, while the drag-then-switch flow
    /// (the one case where the user can't release the mouse) still works. Users who
    /// want dwell at all times turn this off.
    static let defaultDuringDragOnly = true

    /// Slider bounds in milliseconds: a one-second floor so the dwell is always longer
    /// than a normal glance, and a ten-second ceiling so the upper end remains usable.
    static let durationMillisecondRange: ClosedRange<Double> = 1000...10000

    /// The persisted on/off, with a presence check so an absent key returns the default
    /// rather than `bool(forKey:)`'s silent `false`.
    static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: enabledDefaultsKey) != nil else { return defaultEnabled }
        return defaults.bool(forKey: enabledDefaultsKey)
    }

    /// The persisted "drag-and-drop only" gate, presence-checked so an absent key
    /// returns the default rather than `bool(forKey:)`'s silent `false` (which would
    /// silently flip the default to OFF and re-enable always-on dwell).
    static func isDuringDragOnly(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: duringDragOnlyDefaultsKey) != nil else {
            return defaultDuringDragOnly
        }
        return defaults.bool(forKey: duringDragOnlyDefaultsKey)
    }

    /// The persisted duration in **seconds**, clamped to the range, ready for a timer.
    static func duration(from defaults: UserDefaults = .standard) -> TimeInterval {
        durationMilliseconds(from: defaults) / 1000
    }

    /// The persisted duration in milliseconds (the stored unit). Presence-checked so an
    /// absent key returns the default rather than `double(forKey:)`'s silent 0, which
    /// would mean "instant dwell" — exactly the surprise the presence check guards.
    static func durationMilliseconds(from defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: durationDefaultsKey) != nil else { return defaultDurationMilliseconds }
        return clampMilliseconds(defaults.double(forKey: durationDefaultsKey))
    }

    /// Clamp a raw millisecond value into `durationMillisecondRange`, so a stray stored
    /// or typed value never produces an absurd dwell.
    static func clampMilliseconds(_ value: Double) -> Double {
        min(max(value, durationMillisecondRange.lowerBound), durationMillisecondRange.upperBound)
    }

    /// The bundled (enabled, duration, duringDragOnly) the controller reads once per
    /// summon, like the other read-fresh settings. Resolved through `current(from:)`
    /// so a Preferences change takes effect on the next open without a relaunch.
    struct Config: Equatable, Sendable {
        let enabled: Bool
        /// Dwell duration in **seconds**, ready for a timer.
        let duration: TimeInterval
        /// When true, the dwell timer only fires while the user is in a drag (left
        /// mouse button held); released-button hover updates cancel the dwell instead.
        let duringDragOnly: Bool
    }

    /// Resolve the persisted (enabled, duration, duringDragOnly) for the next summon.
    static func current(from defaults: UserDefaults = .standard) -> Config {
        Config(
            enabled: isEnabled(from: defaults),
            duration: duration(from: defaults),
            duringDragOnly: isDuringDragOnly(from: defaults)
        )
    }
}
