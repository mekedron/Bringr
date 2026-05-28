import XCTest
@testable import Bringr

/// Exercises the three-finger press recogniser in isolation from the trackpad and
/// the private MultitouchSupport framework (AC4): every test drives
/// `ThreeFingerPressDetector` with synthetic finger counts and click transitions
/// and asserts the reaction it returns.
final class ThreeFingerTests: XCTestCase {
    // MARK: - AC1: a real three-finger click summons

    func testRestingThreeFingersThenClickPresses() {
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none, "resting three fingers must not summon")
        XCTAssertEqual(detector.handle(.click(down: true)), .press, "the physical click summons")
    }

    func testRampUpThenClickPressesOnClick() {
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.fingerCount(1)), .none)
        XCTAssertEqual(detector.handle(.fingerCount(2)), .none)
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none, "fingers alone never press")
        XCTAssertEqual(detector.handle(.click(down: true)), .press)
    }

    func testClickThenThirdFingerPresses() {
        // The multitouch and click streams may arrive interleaved; a press fires
        // whichever signal completes the pair, here the finger count settling last.
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.fingerCount(2)), .none)
        XCTAssertEqual(detector.handle(.click(down: true)), .none, "two fingers clicked is not the gesture")
        XCTAssertEqual(detector.handle(.fingerCount(3)), .press, "the third finger completes the click")
    }

    // MARK: - The bug: a tap or rest never summons

    func testRestingThreeFingersWithoutClickNeverPresses() {
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none)
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none)
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none)
    }

    func testThreeFingerTapWithoutClickNeverPresses() {
        // Fingers land and lift again with no physical click — a tap, not a press.
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none)
        XCTAssertEqual(detector.handle(.fingerCount(0)), .none)
    }

    // MARK: - AC2: one- and two-finger gestures are unaffected

    func testOneFingerClickDoesNotPress() {
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.fingerCount(1)), .none)
        XCTAssertEqual(detector.handle(.click(down: true)), .none)
    }

    func testTwoFingerClickDoesNotPress() {
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.fingerCount(2)), .none)
        XCTAssertEqual(detector.handle(.click(down: true)), .none)
    }

    func testOrdinaryClickWithNoFingersDoesNotPress() {
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.click(down: true)), .none)
        XCTAssertEqual(detector.handle(.click(down: false)), .none)
    }

    func testFourFingerClickDoesNotPress() {
        var detector = ThreeFingerPressDetector()
        XCTAssertEqual(detector.handle(.fingerCount(4)), .none)
        XCTAssertEqual(detector.handle(.click(down: true)), .none, "four fingers is not exactly the required three")
    }

    // MARK: - The press is an edge, fired once

    func testPressFiresOnceWhileFingersAndClickRemain() {
        var detector = ThreeFingerPressDetector()
        _ = detector.handle(.fingerCount(3))
        XCTAssertEqual(detector.handle(.click(down: true)), .press)
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none, "still three fingers — do not re-summon every frame")
        XCTAssertEqual(detector.handle(.click(down: true)), .none, "a repeated click while latched is ignored")
    }

    // MARK: - AC3: release when the fingers lift (hold-to-select commit)

    func testReleaseWhenFingersLiftAfterClick() {
        var detector = ThreeFingerPressDetector()
        _ = detector.handle(.fingerCount(3))
        XCTAssertEqual(detector.handle(.click(down: true)), .press)
        XCTAssertEqual(detector.handle(.fingerCount(2)), .release)
    }

    func testReleasingTheClickAloneDoesNotCommit() {
        // Lifting the physical click while fingers stay down keeps the menu open;
        // hold-to-select commits on finger-lift, not on the click coming up.
        var detector = ThreeFingerPressDetector()
        _ = detector.handle(.fingerCount(3))
        XCTAssertEqual(detector.handle(.click(down: true)), .press)
        XCTAssertEqual(detector.handle(.click(down: false)), .none, "click up, fingers still down — stay open")
        XCTAssertEqual(detector.handle(.fingerCount(0)), .release, "lifting the fingers commits")
    }

    func testReleaseFiresOnceThenIdle() {
        var detector = ThreeFingerPressDetector()
        _ = detector.handle(.fingerCount(3))
        _ = detector.handle(.click(down: true))
        XCTAssertEqual(detector.handle(.fingerCount(0)), .release)
        XCTAssertEqual(detector.handle(.fingerCount(0)), .none)
    }

    func testPressLatchesThroughAFourthFinger() {
        var detector = ThreeFingerPressDetector()
        _ = detector.handle(.fingerCount(3))
        XCTAssertEqual(detector.handle(.click(down: true)), .press)
        XCTAssertEqual(detector.handle(.fingerCount(4)), .none, "adding a finger keeps the press latched")
        XCTAssertEqual(detector.handle(.fingerCount(1)), .release, "lifting back below three releases")
    }

    // MARK: - Re-arming between gestures

    func testPressReleaseThenPressAgain() {
        var detector = ThreeFingerPressDetector()
        _ = detector.handle(.fingerCount(3))
        XCTAssertEqual(detector.handle(.click(down: true)), .press)
        XCTAssertEqual(detector.handle(.fingerCount(0)), .release)
        _ = detector.handle(.click(down: false))
        // A second three-finger click is recognised cleanly.
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none)
        XCTAssertEqual(detector.handle(.click(down: true)), .press)
    }

    // MARK: - Configurable required count

    func testRequiredFingerCountIsConfigurable() {
        var detector = ThreeFingerPressDetector(requiredFingerCount: 2)
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none)
        XCTAssertEqual(detector.handle(.click(down: true)), .none, "three fingers is not exactly the required two")
        XCTAssertEqual(detector.handle(.fingerCount(2)), .press)
        XCTAssertEqual(detector.handle(.fingerCount(1)), .release)
    }

    // MARK: - Reset

    func testResetClearsLatchedPressAndInputs() {
        var detector = ThreeFingerPressDetector()
        _ = detector.handle(.fingerCount(3))
        _ = detector.handle(.click(down: true))
        detector.reset()
        // After reset nothing is latched and the prior click/fingers are forgotten:
        // dropping fingers is not a release, fingers alone do not press, and only a
        // fresh click with three fingers presses again.
        XCTAssertEqual(detector.handle(.fingerCount(0)), .none)
        XCTAssertEqual(detector.handle(.fingerCount(3)), .none)
        XCTAssertEqual(detector.handle(.click(down: true)), .press)
    }
}
