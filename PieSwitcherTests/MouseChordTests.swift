import XCTest
@testable import PieSwitcher

/// Exercises the chord detection state machine in isolation from the live event stream:
/// every test drives `MouseChordDetector` with synthetic value events and asserts the
/// disposition it returns. Bringr-93j.96 generalised the L+R chord into a multi-method
/// matcher with a configurable hold delay, so most tests now pass a `methods:` set
/// explicitly and assert with `holdDelay = 0` (the immediate-summon path).
final class MouseChordTests: XCTestCase {
    private let leftRight: Set<MouseActivationMethod> = [.leftRight]

    // MARK: - Match completion → summon (delay = 0)

    func testLeftThenRightSummonsImmediatelyWhenDelayIsZero() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.left, at: 0), methods: leftRight), .hold)
        XCTAssertEqual(detector.handle(down(.right, at: 0.05), methods: leftRight), .summon)
        XCTAssertTrue(detector.isChordActive)
    }

    func testRightThenLeftSummonsImmediatelyWhenDelayIsZero() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.right, at: 0), methods: leftRight), .hold)
        XCTAssertEqual(detector.handle(down(.left, at: 0.05), methods: leftRight), .summon)
    }

    // MARK: - Match completion with a non-zero hold delay → caller drives the timer

    func testFullMatchHoldsRatherThanSummonsWhenHoldDelayIsNonZero() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.left, at: 0), methods: leftRight, holdDelay: 0.2), .hold)
        XCTAssertEqual(
            detector.handle(down(.right, at: 0.05), methods: leftRight, holdDelay: 0.2),
            .hold,
            "delay > 0 means the monitor drives the timer; the detector just stays in pursuit"
        )
        XCTAssertEqual(detector.matchedMethod, .leftRight, "full match is visible to the caller")
        XCTAssertFalse(detector.isChordActive, "not chord-active until the monitor calls chordSummoned()")

        detector.chordSummoned()
        XCTAssertTrue(detector.isChordActive)
    }

    // MARK: - Disposition of single clicks (irrelevant or partial-match)

    func testFirstPressIsDeferredNotDelivered() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(
            detector.handle(down(.left, at: 0), methods: leftRight), .hold,
            "the first press of a multi-button method is held, never passed straight through"
        )
    }

    func testSingleLeftClickIsReplayedAsANormalClick() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.left, at: 0), methods: leftRight), .hold)
        XCTAssertEqual(detector.handle(up(.left, at: 0.04), methods: leftRight), .releaseHeldWithCurrent)
    }

    func testSingleRightClickIsReplayedAsANormalClick() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.right, at: 0), methods: leftRight), .hold)
        XCTAssertEqual(detector.handle(up(.right, at: 0.04), methods: leftRight), .releaseHeldWithCurrent)
    }

    func testPressAndHoldBeyondPursuitTimeoutReplaysViaTimeout() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        _ = detector.handle(down(.left, at: 0), methods: leftRight)
        XCTAssertFalse(detector.handleTimeout(at: 0.05), "still within the timeout — keep waiting")
        XCTAssertTrue(detector.handleTimeout(at: 0.12), "timeout elapsed — replay as a normal press")
    }

    func testTimeoutWhenIdleDoesNothing() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertFalse(detector.handleTimeout(at: 1.0))
    }

    func testStrayUpWhenIdlePassesThrough() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(up(.left, at: 0), methods: leftRight), .pass)
    }

    // MARK: - Irrelevant buttons pass through (no enabled method uses them)

    func testIrrelevantButtonPassesThrough() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        // No method uses Middle, so a Middle press has nothing to pursue.
        XCTAssertEqual(detector.handle(down(.middle, at: 0), methods: leftRight), .pass)
    }

    // MARK: - Chord aftermath: presses and releases during the active chord are consumed

    func testChordConsumesSecondPressAndAllReleases() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        _ = detector.handle(down(.left, at: 0), methods: leftRight)
        XCTAssertEqual(detector.handle(down(.right, at: 0.05), methods: leftRight), .summon)
        XCTAssertEqual(detector.handle(up(.left, at: 0.20), methods: leftRight), .consume)
        XCTAssertEqual(detector.handle(up(.right, at: 0.22), methods: leftRight), .consume)
    }

    func testExtraPressesDuringAChordAreConsumed() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        _ = detector.handle(down(.left, at: 0), methods: leftRight)
        _ = detector.handle(down(.right, at: 0.05), methods: leftRight)
        XCTAssertEqual(detector.handle(down(.left, at: 0.10), methods: leftRight), .consume)
        XCTAssertEqual(detector.handle(up(.left, at: 0.12), methods: leftRight), .consume)
        XCTAssertEqual(detector.handle(up(.left, at: 0.30), methods: leftRight), .consume)
        XCTAssertEqual(detector.handle(up(.right, at: 0.32), methods: leftRight), .consume)
    }

    // MARK: - Bringr-93j.94: drag while holding releases the buffered press

    func testMotionWhileHoldingFirstPressReleasesTheHold() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.left, at: 0), methods: leftRight), .hold)
        XCTAssertTrue(
            detector.motionDetected(),
            "a drag during the chord-pursuit window means the user is dragging — release the held press"
        )
        XCTAssertEqual(
            detector.handle(down(.right, at: 0.10), methods: leftRight), .hold,
            "after the release the machine is idle, so the partner is a fresh first press"
        )
    }

    func testMotionWhenIdleDoesNothing() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertFalse(detector.motionDetected())
    }

    func testMotionDuringChordDoesNotReleaseAnything() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        _ = detector.handle(down(.left, at: 0), methods: leftRight)
        _ = detector.handle(down(.right, at: 0.05), methods: leftRight)
        XCTAssertFalse(
            detector.motionDetected(),
            "the chord has already summoned and its presses were consumed — nothing left to release"
        )
        XCTAssertEqual(detector.handle(up(.left, at: 0.20), methods: leftRight), .consume)
        XCTAssertEqual(detector.handle(up(.right, at: 0.22), methods: leftRight), .consume)
    }

    // MARK: - Clean recovery between gestures

    func testAfterAChordANewSingleClickPassesThrough() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        _ = detector.handle(down(.left, at: 0), methods: leftRight)
        _ = detector.handle(down(.right, at: 0.05), methods: leftRight)
        _ = detector.handle(up(.left, at: 0.20), methods: leftRight)
        _ = detector.handle(up(.right, at: 0.22), methods: leftRight)

        XCTAssertEqual(detector.handle(down(.left, at: 0.50), methods: leftRight), .hold)
        XCTAssertEqual(detector.handle(up(.left, at: 0.54), methods: leftRight), .releaseHeldWithCurrent)
    }

    func testResetClearsAHeldPress() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        _ = detector.handle(down(.left, at: 0), methods: leftRight)
        detector.reset()
        XCTAssertEqual(detector.handle(down(.right, at: 0.02), methods: leftRight), .hold)
    }

    // MARK: - Bringr-93j.96: new methods — middle, side buttons, multi-button combos

    func testMiddleAloneMatchesAndSummons() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.middle, at: 0), methods: [.middle]), .summon)
        XCTAssertTrue(detector.isChordActive)
    }

    func testForwardAloneMatchesAndSummons() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.forward, at: 0), methods: [.forward]), .summon)
    }

    func testBackwardAloneMatchesAndSummons() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.backward, at: 0), methods: [.backward]), .summon)
    }

    func testMiddlePlusLeftSummonsOnFullMatch() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.middle, at: 0), methods: [.middleLeft]), .hold)
        XCTAssertEqual(detector.handle(down(.left, at: 0.05), methods: [.middleLeft]), .summon)
    }

    func testForwardPlusBackwardSummonsOnFullMatch() {
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.forward, at: 0), methods: [.forwardBackward]), .hold)
        XCTAssertEqual(detector.handle(down(.backward, at: 0.05), methods: [.forwardBackward]), .summon)
    }

    func testThirdButtonOutsideAnyMethodEndsPursuit() {
        // L is buffered toward L+R. Forward is in no enabled method's required set, so the
        // pursuit can no longer reach a match — replay L and deliver F alongside it.
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.left, at: 0), methods: leftRight), .hold)
        XCTAssertEqual(
            detector.handle(down(.forward, at: 0.05), methods: leftRight),
            .releaseHeldWithCurrent,
            "Forward cannot complete L+R, so the pursuit is abandoned and both events replay in order"
        )
    }

    func testRelevantButPursuitBreakingPressEndsPursuit() {
        // Both L+R and F+B are enabled. L is buffered toward L+R. Pressing F is "relevant"
        // (some method uses F) but adding F to {L} doesn't keep us a subset of L+R (={L,R})
        // OR of F+B (={F,B}) — pursuit can't reach either method, so abandon and replay.
        let methods: Set<MouseActivationMethod> = [.leftRight, .forwardBackward]
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(detector.handle(down(.left, at: 0), methods: methods), .hold)
        XCTAssertEqual(
            detector.handle(down(.forward, at: 0.05), methods: methods), .releaseHeldWithCurrent,
            "{L,F} is a subset of neither {L,R} nor {F,B}, so the pursuit cannot be completed"
        )
    }

    func testMethodsAreIndependentlyMatchable() {
        // Both Middle (single button) and Middle+Left enabled. Middle alone matches Middle;
        // Middle+Left matches the combo. Each press is interpreted against the full set.
        let methods: Set<MouseActivationMethod> = [.middle, .middleLeft]
        var detector = MouseChordDetector(pursuitTimeout: 0.12)
        XCTAssertEqual(
            detector.handle(down(.middle, at: 0), methods: methods, holdDelay: 0),
            .summon,
            "Middle alone exactly matches the single-button method, so it summons at once"
        )
    }

    // MARK: - Helpers

    private func down(_ button: MouseButton, at timestamp: TimeInterval) -> MouseButtonEvent {
        MouseButtonEvent(button: button, phase: .down, timestamp: timestamp)
    }

    private func up(_ button: MouseButton, at timestamp: TimeInterval) -> MouseButtonEvent {
        MouseButtonEvent(button: button, phase: .up, timestamp: timestamp)
    }
}

/// Covers the persisted mouse-activation config (Bringr-93j.96): methods bitmask round-trips,
/// the default set, the "stored 0 vs absent key" distinction for the methods key, the hold
/// delay shape, and the blocking toggle.
final class MouseActivationConfigTests: XCTestCase {

    func testDefaultMethodsIsLeftRight() {
        XCTAssertEqual(MouseActivationConfig.defaultMethods, [.leftRight])
    }

    func testMethodsDefaultsKeyIsStable() {
        XCTAssertEqual(MouseActivationConfig.methodsDefaultsKey, "activation.mouse.methods")
    }

    func testMethodsDefaultWhenUnset() {
        XCTAssertEqual(MouseActivationConfig.methods(from: makeDefaults()), [.leftRight])
        XCTAssertTrue(MouseActivationConfig.isEnabled(from: makeDefaults()))
    }

    func testStoredZeroDisablesEverything() {
        // Storing 0 (the user unchecked every method) must NOT fall back to the default the
        // way an absent key does.
        let defaults = makeDefaults()
        defaults.set(0, forKey: MouseActivationConfig.methodsDefaultsKey)
        XCTAssertTrue(MouseActivationConfig.methods(from: defaults).isEmpty)
        XCTAssertFalse(MouseActivationConfig.isEnabled(from: defaults))
    }

    func testEncodeDecodeRoundTrip() {
        let methods: Set<MouseActivationMethod> = [.leftRight, .middle, .forwardBackward]
        let bitmask = MouseActivationConfig.encodeMethods(methods)
        XCTAssertEqual(MouseActivationConfig.decodeMethods(bitmask: bitmask), methods)
    }

    func testStrayBitsAreMaskedAway() {
        // A future or corrupted bitmask must not produce a phantom case.
        let stray = MouseActivationConfig.encodeMethods([.middle]) | (1 << 30)
        XCTAssertEqual(MouseActivationConfig.decodeMethods(bitmask: stray), [.middle])
    }

    func testEveryMethodHasUniqueBit() {
        var seenBits: Set<Int> = []
        for method in MouseActivationMethod.allCases {
            XCTAssertFalse(seenBits.contains(method.bit), "bit collision for \(method)")
            seenBits.insert(method.bit)
        }
    }

    func testRequiredButtonsAreConsistent() {
        XCTAssertEqual(MouseActivationMethod.leftRight.requiredButtons, [.left, .right])
        XCTAssertEqual(MouseActivationMethod.middle.requiredButtons, [.middle])
        XCTAssertEqual(MouseActivationMethod.middleLeft.requiredButtons, [.middle, .left])
        XCTAssertEqual(MouseActivationMethod.middleRight.requiredButtons, [.middle, .right])
        XCTAssertEqual(MouseActivationMethod.forward.requiredButtons, [.forward])
        XCTAssertEqual(MouseActivationMethod.backward.requiredButtons, [.backward])
        XCTAssertEqual(MouseActivationMethod.forwardBackward.requiredButtons, [.forward, .backward])
    }

    // MARK: Blocking toggle

    func testBlockingDefaultIsOff() {
        // Default must be OFF to honour the CRITICAL no-stutter constraint of Bringr-93j.96.
        XCTAssertFalse(MouseActivationConfig.defaultBlocking)
        XCTAssertFalse(MouseActivationConfig.blocking(from: makeDefaults()))
    }

    func testBlockingStoredValueRoundTrips() {
        for value in [true, false] {
            let defaults = makeDefaults()
            defaults.set(value, forKey: MouseActivationConfig.blockingDefaultsKey)
            XCTAssertEqual(MouseActivationConfig.blocking(from: defaults), value)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "MouseActivationConfigTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create a test UserDefaults suite")
        }
        return defaults
    }
}

/// Covers the persisted mouse hold delay (Bringr-93j.96): the 0 ms default, the ms↔seconds
/// readers, the "stored 0 vs absent key" guard, and clamping.
final class MouseActivationHoldDelayTests: XCTestCase {

    func testDefaultMillisecondsIsZero() {
        XCTAssertEqual(MouseActivationHoldDelay.defaultMilliseconds, 0)
    }

    func testDefaultsKeyIsStable() {
        XCTAssertEqual(MouseActivationHoldDelay.defaultsKey, "activation.mouse.holdDelayMilliseconds")
    }

    func testCurrentDefaultsToZeroWhenUnset() {
        XCTAssertEqual(MouseActivationHoldDelay.milliseconds(from: makeDefaults()), 0)
        XCTAssertEqual(MouseActivationHoldDelay.current(from: makeDefaults()), 0, accuracy: 1e-9)
    }

    func testStoredValueRoundTripsInBothUnits() {
        let defaults = makeDefaults()
        defaults.set(250.0, forKey: MouseActivationHoldDelay.defaultsKey)
        XCTAssertEqual(MouseActivationHoldDelay.milliseconds(from: defaults), 250)
        XCTAssertEqual(MouseActivationHoldDelay.current(from: defaults), 0.25, accuracy: 1e-9)
    }

    func testValuesAreClampedToRange() {
        let high = makeDefaults()
        high.set(5000.0, forKey: MouseActivationHoldDelay.defaultsKey)
        XCTAssertEqual(MouseActivationHoldDelay.milliseconds(from: high), 1000)

        let low = makeDefaults()
        low.set(-25.0, forKey: MouseActivationHoldDelay.defaultsKey)
        XCTAssertEqual(MouseActivationHoldDelay.milliseconds(from: low), 0)
    }

    func testClampMillisecondsHelper() {
        XCTAssertEqual(MouseActivationHoldDelay.clampMilliseconds(1500), 1000)
        XCTAssertEqual(MouseActivationHoldDelay.clampMilliseconds(-5), 0)
        XCTAssertEqual(MouseActivationHoldDelay.clampMilliseconds(300), 300)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "MouseActivationHoldDelayTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create a test UserDefaults suite")
        }
        return defaults
    }
}
