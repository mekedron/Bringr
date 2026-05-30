import CoreGraphics
import XCTest
@testable import PieSwitcher

/// Covers the tap-vs-hold differentiation introduced in Bringr-93j.104: with Lock ON, a
/// release before the hold-delay completes must still fire the focused app's normal click,
/// while a pursuit-broken-by-new-press must still drop everything per Lock semantics. The
/// detector returns the same `.releaseHeldWithCurrent` for both cases — the monitor
/// distinguishes them via `MouseChordMonitor.isReleaseEvent` on the current `CGEvent`.
final class MouseChordMonitorLockTests: XCTestCase {

    func testReleaseHeldWithCurrentFiresForBothTapAndPursuitBreak() {
        var tap = MouseChordDetector(pursuitTimeout: 0.12)
        _ = tap.handle(buttonEvent(.middle, phase: .down, at: 0), methods: [.middle], holdDelay: 0.25)
        XCTAssertEqual(
            tap.handle(buttonEvent(.middle, phase: .up, at: 0.05), methods: [.middle], holdDelay: 0.25),
            .releaseHeldWithCurrent,
            "tap-then-release before the hold delay returns the replay-buffer reaction"
        )

        var broken = MouseChordDetector(pursuitTimeout: 0.12)
        _ = broken.handle(buttonEvent(.middle, phase: .down, at: 0), methods: [.middle], holdDelay: 0.25)
        XCTAssertEqual(
            broken.handle(buttonEvent(.forward, phase: .down, at: 0.05), methods: [.middle], holdDelay: 0.25),
            .releaseHeldWithCurrent,
            "a new press that can't complete any pursued method also returns the replay reaction"
        )
    }

    func testIsReleaseEventDistinguishesUpFromDown() {
        // The predicate the monitor branches on (Bringr-93j.104): mouse-up = tap, replay;
        // mouse-down = pursuit-breaking new press, keep Lock semantics.
        for type in [CGEventType.leftMouseUp, .rightMouseUp, .otherMouseUp] {
            XCTAssertTrue(
                MouseChordMonitor.isReleaseEvent(makeMouseEvent(type: type)),
                "\(type) should count as a release"
            )
        }
        for type in [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            XCTAssertFalse(
                MouseChordMonitor.isReleaseEvent(makeMouseEvent(type: type)),
                "\(type) should not count as a release"
            )
        }
    }

    private func buttonEvent(
        _ button: MouseButton,
        phase: MouseButtonPhase,
        at timestamp: TimeInterval
    ) -> MouseButtonEvent {
        MouseButtonEvent(button: button, phase: phase, timestamp: timestamp)
    }

    private func makeMouseEvent(type: CGEventType) -> CGEvent {
        let button: CGMouseButton
        switch type {
        case .rightMouseDown, .rightMouseUp: button = .right
        case .otherMouseDown, .otherMouseUp: button = .center
        default: button = .left
        }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: .zero,
            mouseButton: button
        ) else {
            fatalError("could not synthesise a CGEvent of type \(type) for the test")
        }
        return event
    }
}
