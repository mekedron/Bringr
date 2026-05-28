import CoreGraphics
import XCTest
@testable import Bringr

/// Covers the configurable modifier-key activation (Bringr-93j.35): the `CGEventFlags`
/// reduction, the persisted mouse-method and modifier-combination readers, the armed-set
/// computation, and the pure `ModifierHoldDetector` edge logic — all in isolation from
/// the live event tap.
final class ModifierActivationTests: XCTestCase {

    // MARK: - CGEventFlags → ModifierCombination

    func testEachFlagMapsToItsModifier() {
        XCTAssertEqual(ModifierCombination(cgFlags: .maskSecondaryFn), .function)
        XCTAssertEqual(ModifierCombination(cgFlags: .maskControl), .control)
        XCTAssertEqual(ModifierCombination(cgFlags: .maskAlternate), .option)
        XCTAssertEqual(ModifierCombination(cgFlags: .maskShift), .shift)
        XCTAssertEqual(ModifierCombination(cgFlags: .maskCommand), .command)
    }

    func testCombinedFlagsMapToTheUnion() {
        let flags: CGEventFlags = [.maskSecondaryFn, .maskCommand]
        XCTAssertEqual(ModifierCombination(cgFlags: flags), [.function, .command])
    }

    func testIrrelevantFlagsAreIgnored() {
        // Caps Lock and the numeric-pad bit must not spoil an otherwise-exact match.
        let flags: CGEventFlags = [.maskSecondaryFn, .maskAlphaShift, .maskNumericPad]
        XCTAssertEqual(ModifierCombination(cgFlags: flags), .function)
    }

    func testNoFlagsMapToEmpty() {
        XCTAssertTrue(ModifierCombination(cgFlags: []).isEmpty)
    }

    // MARK: - Mouse activation method (persistence)

    func testMouseMethodDefaultIsLeftRightClick() {
        XCTAssertEqual(MouseActivationMethod.default, .leftRightClick)
    }

    func testMouseMethodDefaultsKeyIsStable() {
        XCTAssertEqual(MouseActivationMethod.defaultsKey, "activation.mouse.method")
    }

    func testMouseMethodCurrentReadsEveryValue() {
        for method in MouseActivationMethod.allCases {
            let defaults = makeDefaults()
            defaults.set(method.rawValue, forKey: MouseActivationMethod.defaultsKey)
            XCTAssertEqual(MouseActivationMethod.current(from: defaults), method)
        }
    }

    func testMouseMethodFallsBackWhenUnsetOrUnrecognized() {
        XCTAssertEqual(MouseActivationMethod.current(from: makeDefaults()), .default)
        let defaults = makeDefaults()
        defaults.set("not-a-method", forKey: MouseActivationMethod.defaultsKey)
        XCTAssertEqual(MouseActivationMethod.current(from: defaults), .default)
    }

    func testMouseMethodDisplayNamesAreDistinctAndNonEmpty() {
        let names = MouseActivationMethod.allCases.map(\.displayName)
        XCTAssertFalse(names.contains(where: \.isEmpty))
        XCTAssertEqual(Set(names).count, names.count)
    }

    // MARK: - Persisted combinations (defaults & the "cleared vs unset" distinction)

    func testTrackpadDefaultsToFnWhenUnset() {
        XCTAssertEqual(ModifierActivation.trackpad(from: makeDefaults()), .function)
    }

    func testMouseModifiersDefaultToEmptyWhenUnset() {
        XCTAssertTrue(ModifierActivation.mouse(from: makeDefaults()).isEmpty)
    }

    func testStoredCombinationRoundTrips() {
        let defaults = makeDefaults()
        let combo: ModifierCombination = [.control, .option]
        defaults.set(combo.rawValue, forKey: ModifierActivation.trackpadDefaultsKey)
        XCTAssertEqual(ModifierActivation.trackpad(from: defaults), combo)
    }

    func testClearedTrackpadStaysEmptyAndIsNotTheDefault() {
        // Storing 0 means "the user unchecked every key" — disabled — and must NOT fall
        // back to the Fn default the way an absent key does.
        let defaults = makeDefaults()
        defaults.set(0, forKey: ModifierActivation.trackpadDefaultsKey)
        XCTAssertTrue(ModifierActivation.trackpad(from: defaults).isEmpty)
    }

    func testStrayBitsAreMaskedAway() {
        let defaults = makeDefaults()
        defaults.set(ModifierCombination.function.rawValue | (1 << 20), forKey: ModifierActivation.mouseDefaultsKey)
        XCTAssertEqual(ModifierActivation.mouse(from: defaults), .function)
    }

    // MARK: - Armed combinations

    func testArmedByDefaultIsTrackpadFnOnly() {
        // Fresh install: trackpad Fn is armed; the mouse uses left+right click, so its
        // (empty) modifier set is not armed.
        XCTAssertEqual(ModifierActivation.armedCombinations(from: makeDefaults()), [.function])
    }

    func testMouseModifiersArmedOnlyWhenMethodIsModifierKeys() {
        let defaults = makeDefaults()
        defaults.set(ModifierCombination.command.rawValue, forKey: ModifierActivation.mouseDefaultsKey)

        // Method still left+right click → the mouse combo is not armed.
        XCTAssertEqual(ModifierActivation.armedCombinations(from: defaults), [.function])

        // Switch the method → the mouse combo joins the trackpad's.
        defaults.set(MouseActivationMethod.modifierKeys.rawValue, forKey: MouseActivationMethod.defaultsKey)
        XCTAssertEqual(Set(ModifierActivation.armedCombinations(from: defaults)), [.function, .command])
    }

    func testClearedTrackpadDropsOutOfArmedSet() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: ModifierActivation.trackpadDefaultsKey)
        defaults.set(MouseActivationMethod.modifierKeys.rawValue, forKey: MouseActivationMethod.defaultsKey)
        defaults.set(ModifierCombination.option.rawValue, forKey: ModifierActivation.mouseDefaultsKey)
        XCTAssertEqual(ModifierActivation.armedCombinations(from: defaults), [.option])
    }

    func testEmptyMouseSetIsNotArmedEvenInModifierMode() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: ModifierActivation.trackpadDefaultsKey)
        defaults.set(MouseActivationMethod.modifierKeys.rawValue, forKey: MouseActivationMethod.defaultsKey)
        // Mouse modifiers never set → empty → nothing armed at all.
        XCTAssertTrue(ModifierActivation.armedCombinations(from: defaults).isEmpty)
    }

    // MARK: - Detector: rising/falling edges

    func testHoldingAnArmedComboPressesThenReleases() {
        var detector = ModifierHoldDetector()
        XCTAssertEqual(detector.handle(held: .function, armed: [.function]), .press)
        XCTAssertEqual(detector.handle(held: .function, armed: [.function]), .none, "no re-press while still held")
        XCTAssertEqual(detector.handle(held: [], armed: [.function]), .release)
        XCTAssertEqual(detector.handle(held: [], armed: [.function]), .none, "no re-release once idle")
    }

    func testMatchingIsExactSoExtraModifiersDoNotPress() {
        var detector = ModifierHoldDetector()
        XCTAssertEqual(detector.handle(held: [.function, .shift], armed: [.function]), .none,
                       "holding Fn+Shift is not exactly Fn")
    }

    func testAddingAModifierToAnActiveComboReleasesIt() {
        var detector = ModifierHoldDetector()
        XCTAssertEqual(detector.handle(held: .command, armed: [.command]), .press)
        XCTAssertEqual(detector.handle(held: [.command, .shift], armed: [.command]), .release,
                       "⌘⇧ is no longer the armed ⌘, so the menu gets out of the way")
    }

    func testCombinationRequiresEveryKey() {
        let armed: [ModifierCombination] = [[.function, .control]]
        var detector = ModifierHoldDetector()
        XCTAssertEqual(detector.handle(held: .function, armed: armed), .none, "Fn alone is not the full combo")
        XCTAssertEqual(detector.handle(held: [.function, .control], armed: armed), .press)
        XCTAssertEqual(detector.handle(held: .function, armed: armed), .release, "dropping Control ends it")
    }

    func testStaysActiveAcrossDistinctArmedCombos() {
        // With two armed combos, sliding from one to the other never re-fires: it stays
        // active until no armed combo is held.
        let armed: [ModifierCombination] = [.function, [.command, .option]]
        var detector = ModifierHoldDetector()
        XCTAssertEqual(detector.handle(held: .function, armed: armed), .press)
        XCTAssertEqual(detector.handle(held: [.command, .option], armed: armed), .none,
                       "moved to the other armed combo while still matching — no second press")
        XCTAssertEqual(detector.handle(held: [], armed: armed), .release)
    }

    func testNoArmedCombosNeverPresses() {
        var detector = ModifierHoldDetector()
        XCTAssertEqual(detector.handle(held: .function, armed: []), .none)
        XCTAssertEqual(detector.handle(held: [.command, .shift], armed: []), .none)
    }

    func testEmptyArmedEntryIsIgnored() {
        var detector = ModifierHoldDetector()
        // An empty armed combination can never be "held" — releasing all keys must not
        // be read as matching it.
        XCTAssertEqual(detector.handle(held: [], armed: [[]]), .none)
    }

    func testResetClearsLatchedActivation() {
        var detector = ModifierHoldDetector()
        XCTAssertEqual(detector.handle(held: .function, armed: [.function]), .press)
        detector.reset()
        // After reset the prior hold is forgotten: still holding Fn presses afresh rather
        // than being treated as already-active.
        XCTAssertEqual(detector.handle(held: .function, armed: [.function]), .press)
    }

    // MARK: - Names (Preferences caption)

    func testNamesListsSelectedKeysInOrder() {
        XCTAssertEqual(ModifierCombination([.function, .command]).names, "Fn + Command")
        XCTAssertEqual(ModifierCombination.control.names, "Control")
        XCTAssertEqual(ModifierCombination([]).names, "")
    }

    // MARK: - Fixtures

    /// An isolated `UserDefaults` suite so persistence tests never touch the real domain.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ModifierActivationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create a test UserDefaults suite")
        }
        return defaults
    }
}
