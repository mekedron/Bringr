import AppKit
import CoreGraphics
import Foundation
import os

// MARK: - Detector (pure)

/// What an input means for the three-finger gesture.
///
/// - `none`: nothing changed (the gesture is neither beginning nor ending).
/// - `press`: a real three-finger click just happened — summon.
/// - `release`: the fingers lifted back below the required count — the signal
///   hold-to-select uses to commit (US-009).
enum ThreeFingerReaction: Equatable, Sendable {
    case none
    case press
    case release
}

/// One signal fed to the detector: either the current finger count from the
/// multitouch stream, or a physical trackpad click transition. Keeping both as
/// plain values lets the whole recogniser be unit-tested without a trackpad (AC4).
enum ThreeFingerInput: Equatable, Sendable {
    /// The number of fingers on the trackpad is now this.
    case fingerCount(Int)
    /// The trackpad was physically clicked (`down: true`) or the click released.
    case click(down: Bool)
}

/// Recognises a three-finger trackpad *click* — not a mere touch — from a stream
/// of finger counts and click transitions, and reports when it begins and ends.
///
/// This is the host-independent half of the activation (AC4): it never touches the
/// trackpad or any private framework, it only consumes the value inputs above, so
/// all of its behaviour is unit-tested directly. A press requires a physical click
/// while exactly `requiredFingerCount` fingers are present — resting or tapping
/// three fingers is therefore ignored (the bug this fixes). The press latches
/// until the fingers lift back below the required count, which is the release that
/// hold-to-select commits on; lifting the click alone does not commit. Counts of
/// one or two fingers never reach the required count, so those clicks are ignored
/// (AC2), as is a four-or-more-finger click.
struct ThreeFingerPressDetector {
    /// The number of simultaneous fingers that, when clicked, counts as a press.
    /// Configurable so the recognised gesture is tunable and testable; v1 uses three.
    let requiredFingerCount: Int

    /// The most recent finger count reported by the trackpad.
    private var fingerCount = 0
    /// Whether the trackpad is physically clicked right now.
    private var isClicking = false
    /// Whether a press is currently latched, awaiting the fingers to lift.
    private var isPressed = false
    /// Whether the live tap swallowed the current press's mouse-down, so it can
    /// swallow the matching mouse-up too (Bringr-93j.23).
    private var clickSuppressed = false

    init(requiredFingerCount: Int = 3) {
        self.requiredFingerCount = requiredFingerCount
    }

    /// Feed one input and get what it means for the gesture. A press fires on the
    /// rising edge of "clicked with exactly the required fingers" (in either order,
    /// so the multitouch and click streams may arrive interleaved).
    mutating func handle(_ input: ThreeFingerInput) -> ThreeFingerReaction {
        switch input {
        case .fingerCount(let count): fingerCount = count
        case .click(let down): isClicking = down
        }

        if isPressed {
            guard fingerCount < requiredFingerCount else { return .none }
            isPressed = false
            return .release
        }

        guard isClicking, fingerCount == requiredFingerCount else { return .none }
        isPressed = true
        return .press
    }

    /// Feed a physical click transition and get back both the gesture reaction and
    /// whether the live tap should *swallow* this click so it never reaches the app
    /// behind the menu (Bringr-93j.23).
    ///
    /// A mouse-down is swallowed exactly when it completes a three-finger press; its
    /// matching mouse-up is swallowed iff its down was, so the app behind never sees
    /// an unbalanced click (a lone up would otherwise end a drag it never began).
    /// Ordinary one-/two-finger clicks complete no press, so they pass through
    /// untouched (AC2). When the third finger lands *after* the click the down has
    /// already been delivered and cannot be recalled, so that rare interleave still
    /// summons but does not suppress — it is the one case where the click leaks.
    mutating func handleClick(down: Bool) -> (reaction: ThreeFingerReaction, suppress: Bool) {
        let reaction = handle(.click(down: down))
        if down {
            clickSuppressed = (reaction == .press)
            return (reaction, clickSuppressed)
        }
        let suppress = clickSuppressed
        clickSuppressed = false
        return (reaction, suppress)
    }

    /// Clear all state, so a stale press or click from a previous session never
    /// resolves into a new one. Called when the monitor (re)starts.
    mutating func reset() {
        fingerCount = 0
        isClicking = false
        isPressed = false
        clickSuppressed = false
    }
}

// MARK: - MultitouchSupport private API (resolved at runtime)

private typealias MTDeviceRef = UnsafeMutableRawPointer

/// The contact-frame callback MultitouchSupport invokes per frame. The second
/// argument is the touch array; we never dereference it (its struct ABI is
/// private and fragile), reading only `numTouches`, so it is an opaque pointer.
private typealias MTContactCallback = @convention(c) (
    MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

private typealias MTDeviceCreateDefaultFunc = @convention(c) () -> MTDeviceRef?
private typealias MTRegisterCallbackFunc = @convention(c) (MTDeviceRef?, MTContactCallback) -> Void
private typealias MTUnregisterCallbackFunc = @convention(c) (MTDeviceRef?, MTContactCallback) -> Void
private typealias MTDeviceStartFunc = @convention(c) (MTDeviceRef?, Int32) -> Void
private typealias MTDeviceStopFunc = @convention(c) (MTDeviceRef?) -> Void

/// The C contact callback. It cannot capture context — MultitouchSupport's
/// callback has no refcon parameter — and it fires on a private MultitouchSupport
/// thread, so it reads the frame's finger count, hops to the main actor (FIFO via
/// the main queue, so edge detection sees frames in order), and routes through the
/// single active monitor.
private let threeFingerContactCallback: MTContactCallback = { _, _, numTouches, _, _ in
    let count = Int(numTouches)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            ThreeFingerMonitor.active?.handleFrame(touchCount: count)
        }
    }
    return 0
}

// MARK: - Live monitor (MultitouchSupport)

/// Observes the trackpad through the private MultitouchSupport framework for the
/// finger count and an active `CGEventTap` for the physical click, feeds both into a
/// `ThreeFingerPressDetector`, and fires `onPress` only on a real three-finger click
/// (and `onRelease` when the fingers lift).
///
/// **Why an active tap for the click (Bringr-93j.23):** a three-finger press's click
/// must not also land on the app *behind* the menu (clicking a button, moving the
/// caret, etc.). Only an active tap can *consume* an event, so the click is detected
/// and swallowed in one place. What a tap cannot reach is the WindowServer's own
/// multi-finger gestures (Mission Control, App Exposé, swipe-between-pages): those
/// are interpreted below the event-tap layer and are not userspace-suppressible — but
/// they require a *swipe*, not a stationary *click*, so a real three-finger press
/// never sets them off. Two-finger gestures (scroll, magnify) cannot physically
/// co-occur with three fingers down, so there is nothing further to hold back.
///
/// The MultitouchSupport framework is loaded at runtime with `dlopen`/`dlsym` rather
/// than linked, so if it (or any symbol, or any trackpad) is missing, finger reading
/// fails gracefully, logs, and the app keeps running with three-finger activation
/// disabled (AC3). The click tap needs Accessibility/Input-Monitoring permission; if
/// it cannot be created we fall back to a passive global monitor so the summon still
/// works (without click suppression), and upgrade to the tap once permission is
/// granted — call `start()` again, after the mouse-chord tap, to keep this tap at the
/// head of the chain so it wins the three-finger click. Finger reading and ordinary
/// clicks both stay untouched (AC2).
@MainActor
final class ThreeFingerMonitor {
    /// The single active monitor, so the context-free C callback can route frames
    /// back to it. There is only ever one, owned by `AppDelegate` for the app's
    /// lifetime; held weakly so a late frame after `stop()` is a no-op.
    fileprivate static weak var active: ThreeFingerMonitor?

    private var detector: ThreeFingerPressDetector
    private let onPress: () -> Void
    private let onRelease: () -> Void

    private var dlHandle: UnsafeMutableRawPointer?
    private var device: MTDeviceRef?
    private var stopFunc: MTDeviceStopFunc?
    private var unregisterFunc: MTUnregisterCallbackFunc?
    /// Active tap for the physical trackpad click, so a three-finger press's click can
    /// be consumed instead of leaking to the app behind the menu (Bringr-93j.23).
    private var clickTap: CFMachPort?
    private var clickRunLoopSource: CFRunLoopSource?
    /// Passive global click monitor used only when the tap cannot be created (no
    /// permission): the summon still works, but the click is not suppressed.
    private var clickFallbackMonitor: Any?

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private let log = Logger(subsystem: "com.mekedron.Bringr", category: "ThreeFinger")

    init(
        requiredFingerCount: Int = 3,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void = {}
    ) {
        self.detector = ThreeFingerPressDetector(requiredFingerCount: requiredFingerCount)
        self.onPress = onPress
        self.onRelease = onRelease
    }

    /// Whether the trackpad monitor is currently installed and running.
    var isRunning: Bool { device != nil }

    /// Start finger reading and install the click-detection path. Idempotent and
    /// safe to call again to upgrade the click fallback to a tap once permission is
    /// granted; returns whether finger reading is up (the core requirement). Logs and
    /// degrades gracefully when MultitouchSupport, a trackpad, or permission is absent.
    @discardableResult
    func start() -> Bool {
        let running = startMultitouch()
        installClickPath()
        return running
    }

    /// Load MultitouchSupport, register the contact callback, and start the default
    /// trackpad. Idempotent; returns `false` (and logs) when the framework, a symbol,
    /// or a trackpad is unavailable, leaving the app running normally.
    private func startMultitouch() -> Bool {
        guard device == nil else { return true }

        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            log.error("MultitouchSupport unavailable — three-finger activation disabled on this host.")
            return false
        }

        guard
            let createSym = dlsym(handle, "MTDeviceCreateDefault"),
            let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
            let startSym = dlsym(handle, "MTDeviceStart"),
            let stopSym = dlsym(handle, "MTDeviceStop"),
            let unregisterSym = dlsym(handle, "MTUnregisterContactFrameCallback")
        else {
            log.error("MultitouchSupport symbols missing — three-finger activation disabled.")
            dlclose(handle)
            return false
        }

        let create = unsafeBitCast(createSym, to: MTDeviceCreateDefaultFunc.self)
        let register = unsafeBitCast(registerSym, to: MTRegisterCallbackFunc.self)
        let startDevice = unsafeBitCast(startSym, to: MTDeviceStartFunc.self)
        let stop = unsafeBitCast(stopSym, to: MTDeviceStopFunc.self)
        let unregister = unsafeBitCast(unregisterSym, to: MTUnregisterCallbackFunc.self)

        guard let newDevice = create() else {
            log.error("No multitouch device found — three-finger activation disabled (no trackpad?).")
            dlclose(handle)
            return false
        }

        Self.active = self
        detector.reset()
        register(newDevice, threeFingerContactCallback)
        startDevice(newDevice, 0)

        dlHandle = handle
        device = newDevice
        stopFunc = stop
        unregisterFunc = unregister

        log.info("Three-finger finger reading installed.")
        return true
    }

    /// Install the physical-click detector: an active tap if permission allows (so a
    /// three-finger click can be swallowed), otherwise a passive fallback monitor (so
    /// the summon still works without suppression). Re-running upgrades fallback → tap.
    private func installClickPath() {
        guard clickTap == nil else { return } // already suppression-capable
        if installClickTap() {
            removeClickFallbackMonitor() // upgraded from the fallback
        } else if clickFallbackMonitor == nil {
            installClickFallbackMonitor()
        }
    }

    /// Create the active click tap. Returns `false` (and logs) when the tap cannot be
    /// created, which happens without Accessibility/Input-Monitoring permission.
    private func installClickTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ThreeFingerMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return MainActor.assumeIsolated { monitor.handleTap(type: type, event: event) }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("Could not create three-finger click tap — permission missing; click will not be suppressed.")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        clickTap = tap
        clickRunLoopSource = source
        log.info("Three-finger click tap installed (suppression active).")
        return true
    }

    /// The permission-free fallback: a passive global monitor that detects the click
    /// but cannot consume it, so the summon works while the click still leaks.
    private func installClickFallbackMonitor() {
        clickFallbackMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleFallbackClick(down: event.type == .leftMouseDown)
            }
        }
    }

    private func removeClickFallbackMonitor() {
        if let clickFallbackMonitor { NSEvent.removeMonitor(clickFallbackMonitor) }
        clickFallbackMonitor = nil
    }

    /// Stop the device, unregister the callback, tear down the click path, and unload
    /// the framework.
    func stop() {
        if let device {
            stopFunc?(device)
            unregisterFunc?(device, threeFingerContactCallback)
        }
        if let clickTap { CGEvent.tapEnable(tap: clickTap, enable: false) }
        if let clickRunLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), clickRunLoopSource, .commonModes) }
        clickTap = nil
        clickRunLoopSource = nil
        removeClickFallbackMonitor()
        if Self.active === self { Self.active = nil }
        device = nil
        stopFunc = nil
        unregisterFunc = nil
        if let dlHandle { dlclose(dlHandle) }
        dlHandle = nil
        detector.reset()
    }

    /// Feed one frame's finger count to the detector. `fileprivate` so the C
    /// callback can reach it; runs on the main actor.
    fileprivate func handleFrame(touchCount: Int) {
        react(to: detector.handle(.fingerCount(touchCount)))
    }

    /// Handle one event from the click tap: feed the click to the detector and
    /// *swallow* it when it belongs to a three-finger press, so the click never
    /// reaches the app behind the menu (Bringr-93j.23). Re-enables the tap if the
    /// system disabled it for running over budget.
    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let clickTap { CGEvent.tapEnable(tap: clickTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let down: Bool
        switch type {
        case .leftMouseDown: down = true
        case .leftMouseUp: down = false
        default: return Unmanaged.passUnretained(event)
        }
        let (reaction, suppress) = detector.handleClick(down: down)
        react(to: reaction)
        return suppress ? nil : Unmanaged.passUnretained(event)
    }

    /// The permission-free path's click handler: detect (but never suppress) the
    /// click. Used only when the active tap could not be created.
    private func handleFallbackClick(down: Bool) {
        react(to: detector.handleClick(down: down).reaction)
    }

    /// Perform the detector's verdict.
    private func react(to reaction: ThreeFingerReaction) {
        switch reaction {
        case .press: onPress()
        case .release: onRelease()
        case .none: break
        }
    }
}
