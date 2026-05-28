import AppKit
import CoreGraphics
import Foundation
import os

// MARK: - Modifier combination

/// A combination of modifier keys that, held together, summons the menu (Bringr-93j.35).
/// An `OptionSet` so any subset of the five keys can be required at once; the raw `Int`
/// bitmask is what Preferences persists, so a whole combination round-trips through a
/// single `@AppStorage`-friendly value.
struct ModifierCombination: OptionSet, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let function = ModifierCombination(rawValue: 1 << 0)
    static let control = ModifierCombination(rawValue: 1 << 1)
    static let option = ModifierCombination(rawValue: 1 << 2)
    static let shift = ModifierCombination(rawValue: 1 << 3)
    static let command = ModifierCombination(rawValue: 1 << 4)

    /// Every modifier we recognise — used to mask away stray bits read from storage and
    /// to enumerate the Preferences checkboxes.
    static let all: ModifierCombination = [.function, .control, .option, .shift, .command]

    /// One selectable key for the Preferences UI, in the order macOS conventionally
    /// lists them (Fn, then ⌃ ⌥ ⇧ ⌘).
    struct Key: Identifiable, Sendable {
        let modifier: ModifierCombination
        let name: String
        var id: Int { modifier.rawValue }
    }

    static let keys: [Key] = [
        Key(modifier: .function, name: "Fn"),
        Key(modifier: .control, name: "Control"),
        Key(modifier: .option, name: "Option"),
        Key(modifier: .shift, name: "Shift"),
        Key(modifier: .command, name: "Command")
    ]

    /// The modifiers a `CGEvent` reports as held, reduced to the five we track so
    /// unrelated bits (Caps Lock, numeric pad) never spoil an exact match.
    init(cgFlags: CGEventFlags) {
        var combo: ModifierCombination = []
        if cgFlags.contains(.maskSecondaryFn) { combo.insert(.function) }
        if cgFlags.contains(.maskControl) { combo.insert(.control) }
        if cgFlags.contains(.maskAlternate) { combo.insert(.option) }
        if cgFlags.contains(.maskShift) { combo.insert(.shift) }
        if cgFlags.contains(.maskCommand) { combo.insert(.command) }
        self = combo
    }

    /// The selected keys as "Fn + Command", for the Preferences caption.
    var names: String {
        Self.keys.filter { contains($0.modifier) }.map(\.name).joined(separator: " + ")
    }
}

// MARK: - Mouse activation method

/// How the mouse summons the menu (Bringr-93j.35): either a held modifier combination
/// or the simultaneous left+right click (US-007). Persisted and read fresh, mirroring
/// the other settings enums, so a Preferences change applies without a relaunch.
enum MouseActivationMethod: String, CaseIterable, Sendable {
    /// Press the left and right buttons together — the original v1 mouse trigger.
    case leftRightClick
    /// Hold the configured modifier combination, like the trackpad.
    case modifierKeys

    /// Left+right click is the default: it preserves the working v1 trigger and summons
    /// out of the box, whereas the default mouse modifier set is empty (nothing to hold).
    static let `default`: MouseActivationMethod = .leftRightClick

    /// `UserDefaults` key backing the persisted choice. Single source of truth shared by
    /// the Preferences `@AppStorage` and `current(from:)` so they cannot drift.
    static let defaultsKey = "activation.mouse.method"

    /// Human-readable name for the Preferences picker.
    var displayName: String {
        switch self {
        case .leftRightClick: return "Left + right click together"
        case .modifierKeys: return "Hold modifier keys"
        }
    }

    /// The persisted method, falling back to `.default` when unset or unrecognized.
    static func current(from defaults: UserDefaults = .standard) -> MouseActivationMethod {
        guard let raw = defaults.string(forKey: defaultsKey),
              let method = MouseActivationMethod(rawValue: raw) else {
            return .default
        }
        return method
    }
}

// MARK: - Persisted modifier combinations

/// The persisted modifier-key activation for the mouse and the trackpad, plus the set
/// of combinations currently "armed". Read fresh like the other settings, so a change
/// applies immediately without a relaunch.
enum ModifierActivation {
    /// `UserDefaults` keys backing the two persisted combinations.
    static let trackpadDefaultsKey = "activation.trackpad.modifiers"
    static let mouseDefaultsKey = "activation.mouse.modifiers"

    /// The trackpad defaults to Fn: holding Fn summons the menu with no trackpad gesture.
    static let trackpadDefault: ModifierCombination = .function
    /// The mouse defaults to no modifiers (its default method is left+right click).
    static let mouseDefault: ModifierCombination = []

    static func trackpad(from defaults: UserDefaults = .standard) -> ModifierCombination {
        read(trackpadDefaultsKey, default: trackpadDefault, from: defaults)
    }

    static func mouse(from defaults: UserDefaults = .standard) -> ModifierCombination {
        read(mouseDefaultsKey, default: mouseDefault, from: defaults)
    }

    /// A stored `0` means "explicitly cleared" (the user unchecked every key, disabling
    /// that path) — distinct from "never set", which yields the default. So an absent key
    /// gets the default while a cleared one stays empty. Stray bits are masked away.
    private static func read(
        _ key: String,
        default fallback: ModifierCombination,
        from defaults: UserDefaults
    ) -> ModifierCombination {
        guard let raw = defaults.object(forKey: key) as? Int else { return fallback }
        return ModifierCombination(rawValue: raw).intersection(.all)
    }

    /// Every combination that should summon the menu right now: the trackpad's (always,
    /// since the trackpad only offers modifier activation) plus the mouse's when its
    /// method is set to modifier keys. Empty combinations are dropped, so unchecking
    /// every key disables that path rather than arming "no modifiers".
    static func armedCombinations(from defaults: UserDefaults = .standard) -> [ModifierCombination] {
        var armed: [ModifierCombination] = []
        let trackpad = trackpad(from: defaults)
        if !trackpad.isEmpty { armed.append(trackpad) }
        if MouseActivationMethod.current(from: defaults) == .modifierKeys {
            let mouse = mouse(from: defaults)
            if !mouse.isEmpty { armed.append(mouse) }
        }
        return armed
    }
}

// MARK: - Detector (pure)

/// Recognises when the held modifiers match one of the armed combinations, emitting a
/// single `press` on the rising edge and a single `release` on the falling edge — the
/// same press/release shape the hold-capable triggers feed the interaction state machine
/// (US-009). Pure and value-typed, so the edge logic is unit-tested without an event tap.
///
/// Matching is *exact*: the held set must equal an armed set. Holding extra modifiers
/// never summons, and adding a modifier to an active combination ends it — so a genuine
/// shortcut like ⌘⇧4 never fires a ⌘-armed trigger, and the menu gets out of the way the
/// moment the chord changes.
struct ModifierHoldDetector {
    enum Reaction: Equatable, Sendable {
        case none
        case press
        case release
    }

    /// Whether an armed combination is currently held. Read-only to callers; only
    /// `handle` transitions it, so the detector is the single source of truth.
    private(set) var isActive = false

    /// Feed the currently-held modifiers and the armed combinations and get the edge.
    mutating func handle(held: ModifierCombination, armed: [ModifierCombination]) -> Reaction {
        let matches = armed.contains { !$0.isEmpty && $0 == held }
        switch (matches, isActive) {
        case (true, false):
            isActive = true
            return .press
        case (false, true):
            isActive = false
            return .release
        case (true, true), (false, false):
            return .none
        }
    }

    /// Clear the latched state, so a stale hold from a previous session never resolves
    /// into a new one. Called when the monitor (re)starts.
    mutating func reset() { isActive = false }
}

// MARK: - Live monitor (CGEventTap on flagsChanged)

/// Watches global modifier-key changes through a `CGEventTap` and fires `onPress` /
/// `onRelease` when the held modifiers start / stop matching an armed combination
/// (Bringr-93j.35). This is the trackpad's only activation and the mouse's modifier-key
/// option; it replaces the unreliable three-finger trackpad press.
///
/// The tap **never consumes** an event — modifier keys must keep working everywhere — it
/// only observes and always passes the event through. It needs Accessibility permission
/// like the mouse-chord tap, so `start()` fails gracefully without it and is retried once
/// permission is granted. The armed combinations are read fresh on every change, so a
/// Preferences change takes effect immediately with no relaunch.
@MainActor
final class ModifierHoldMonitor {
    private var detector = ModifierHoldDetector()
    private let onPress: () -> Void
    private let onRelease: () -> Void
    /// The armed combinations, read fresh on each modifier change so Preferences edits
    /// apply at once. Injected so tests can pass fixed combinations.
    private let armedProvider: () -> [ModifierCombination]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let log = Logger(subsystem: "com.mekedron.Bringr", category: "ModifierHold")

    init(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void = {},
        armedProvider: @escaping () -> [ModifierCombination] = { ModifierActivation.armedCombinations() }
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.armedProvider = armedProvider
    }

    /// Whether the tap is currently installed.
    var isRunning: Bool { eventTap != nil }

    /// Install the event tap. Idempotent; returns `false` (and logs) if the tap cannot be
    /// created, which happens when the process lacks Accessibility permission. Call again
    /// once permission is granted to retry.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ModifierHoldMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // Active-but-pass-through, matching the proven mouse-chord tap's permission
            // path; the callback always returns the event, so no modifier is ever eaten.
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("Could not create modifier-hold tap — Accessibility permission likely missing.")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        detector.reset()
        log.info("Modifier-hold tap installed.")
        return true
    }

    /// Remove the tap and clear latched state.
    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        detector.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a slow/over-budget tap; re-enable and pass through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

        let held = ModifierCombination(cgFlags: event.flags)
        switch detector.handle(held: held, armed: armedProvider()) {
        case .press: onPress()
        case .release: onRelease()
        case .none: break
        }
        return Unmanaged.passUnretained(event)
    }
}
