import AppKit
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

    /// Clear all state, so a stale press or click from a previous session never
    /// resolves into a new one. Called when the monitor (re)starts.
    mutating func reset() {
        fingerCount = 0
        isClicking = false
        isPressed = false
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
/// finger count and a global `NSEvent` monitor for the physical click, feeds both
/// into a `ThreeFingerPressDetector`, and fires `onPress` only on a real three-
/// finger click (and `onRelease` when the fingers lift).
///
/// The framework is loaded at runtime with `dlopen`/`dlsym` rather than linked, so
/// if it (or any symbol, or any trackpad) is missing, `start()` fails gracefully,
/// logs, and the app keeps running with three-finger activation simply disabled
/// (AC3). Both observers are passive — they never consume events — so every other
/// gesture, including ordinary clicks, passes through to the system untouched (AC2).
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
    /// Global passive monitor for the physical trackpad click that gates a press.
    private var clickMonitor: Any?

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

    /// Load MultitouchSupport, register the contact callback, and start the
    /// default trackpad. Idempotent; returns `false` (and logs) when the framework,
    /// a symbol, or a trackpad is unavailable, leaving the app running normally.
    @discardableResult
    func start() -> Bool {
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

        // The physical click that turns a three-finger rest into a press. A global
        // NSEvent monitor is passive (it never consumes the click) and needs no
        // Accessibility permission for mouse events, keeping this path permission-free.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleClick(down: event.type == .leftMouseDown)
            }
        }

        log.info("Three-finger trackpad monitor installed.")
        return true
    }

    /// Stop the device, unregister the callback, and unload the framework.
    func stop() {
        if let device {
            stopFunc?(device)
            unregisterFunc?(device, threeFingerContactCallback)
        }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
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

    /// Feed a physical trackpad click transition to the detector. The click is what
    /// distinguishes a real three-finger press from a rest or tap.
    private func handleClick(down: Bool) {
        react(to: detector.handle(.click(down: down)))
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
