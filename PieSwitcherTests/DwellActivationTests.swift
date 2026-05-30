import Foundation
import XCTest
@testable import PieSwitcher

/// Covers the dwell-to-activate persistence model (Bringr-93j.105): the defaults
/// round-trip, the presence-checked readers that distinguish "absent" from
/// "explicitly off / explicitly zero", and the millisecond/second unit boundary.
/// All against an ephemeral `UserDefaults` suite — never the live system or
/// `.standard`.
final class DwellActivationTests: XCTestCase {
    private let durationAccuracy: TimeInterval = 0.0001

    // MARK: - Defaults & persistence round-trip

    func testCurrentReturnsDefaultWhenNothingPersisted() {
        let config = DwellActivation.current(from: makeDefaults())
        XCTAssertEqual(config.enabled, DwellActivation.defaultEnabled)
        XCTAssertEqual(
            config.duration,
            DwellActivation.defaultDurationMilliseconds / 1000,
            accuracy: durationAccuracy
        )
    }

    func testIsEnabledReadsPersistedValue() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: DwellActivation.enabledDefaultsKey)
        XCTAssertFalse(DwellActivation.isEnabled(from: defaults))

        defaults.set(true, forKey: DwellActivation.enabledDefaultsKey)
        XCTAssertTrue(DwellActivation.isEnabled(from: defaults))
    }

    /// The presence-check pattern is load-bearing: without it, `bool(forKey:)` returns
    /// `false` for an absent key and would silently flip the default to OFF.
    func testIsEnabledFallsBackToDefaultWhenAbsent() {
        let defaults = makeDefaults()
        XCTAssertEqual(DwellActivation.isEnabled(from: defaults), DwellActivation.defaultEnabled)
    }

    func testDurationReadsPersistedMilliseconds() {
        let defaults = makeDefaults()
        defaults.set(3500.0, forKey: DwellActivation.durationDefaultsKey)
        XCTAssertEqual(DwellActivation.duration(from: defaults), 3.5, accuracy: durationAccuracy)
        XCTAssertEqual(
            DwellActivation.durationMilliseconds(from: defaults), 3500, accuracy: durationAccuracy
        )
    }

    /// Same presence-check rationale for the duration: without it, `double(forKey:)`
    /// returns 0 for a missing key and would yield an instant (= 0 s) dwell.
    func testDurationFallsBackToDefaultWhenAbsent() {
        let defaults = makeDefaults()
        XCTAssertEqual(
            DwellActivation.durationMilliseconds(from: defaults),
            DwellActivation.defaultDurationMilliseconds,
            accuracy: durationAccuracy
        )
    }

    // MARK: - Clamping

    func testClampsBelowMinimum() {
        let defaults = makeDefaults()
        defaults.set(50.0, forKey: DwellActivation.durationDefaultsKey)
        let clamped = DwellActivation.durationMilliseconds(from: defaults)
        XCTAssertEqual(
            clamped,
            DwellActivation.durationMillisecondRange.lowerBound,
            accuracy: durationAccuracy,
            "below-range stored value must clamp up to the slider floor"
        )
    }

    func testClampsAboveMaximum() {
        let defaults = makeDefaults()
        defaults.set(60_000.0, forKey: DwellActivation.durationDefaultsKey)
        let clamped = DwellActivation.durationMilliseconds(from: defaults)
        XCTAssertEqual(
            clamped,
            DwellActivation.durationMillisecondRange.upperBound,
            accuracy: durationAccuracy,
            "above-range stored value must clamp down to the slider ceiling"
        )
    }

    func testClampMillisecondsAcceptsInRangeValue() {
        let value = (DwellActivation.durationMillisecondRange.lowerBound
                     + DwellActivation.durationMillisecondRange.upperBound) / 2
        XCTAssertEqual(DwellActivation.clampMilliseconds(value), value, accuracy: durationAccuracy)
    }

    // MARK: - Bundled config

    /// The bundled `Config` the controller reads at summon must reflect both knobs at once.
    func testCurrentBundlesBothKnobs() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: DwellActivation.enabledDefaultsKey)
        defaults.set(4000.0, forKey: DwellActivation.durationDefaultsKey)

        let config = DwellActivation.current(from: defaults)
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.duration, 4.0, accuracy: durationAccuracy)
    }

    func testDefaultsLandWithinAdvertisedRange() {
        // A sanity check that the documented default sits in the documented slider range,
        // so future tweaks to either don't silently put the default out of bounds.
        let range = DwellActivation.durationMillisecondRange
        XCTAssertTrue(range.contains(DwellActivation.defaultDurationMilliseconds))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DwellActivationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create a test UserDefaults suite")
        }
        return defaults
    }
}
