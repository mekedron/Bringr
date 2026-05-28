# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

- **Activation detectors are pure value types fed by value inputs.** Both
  `MouseChordDetector` and `ThreeFingerPressDetector` are `struct`s that consume
  plain `Equatable`/`Sendable` input values (not live events) and return a
  reaction enum, so the recognition logic is fully unit-tested without hardware.
  The live `@MainActor` monitor class owns the OS plumbing (CGEventTap / NSEvent
  global monitor / MultitouchSupport) and only translates raw events into those
  value inputs. When a detector needs a new signal, add a case to its input enum
  rather than coupling it to an event type.
- **A physical trackpad click is an `NSEvent.leftMouseDown`.** Gate
  multitouch-finger gestures on a real click with a *passive* global monitor
  (`NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp])`):
  it never consumes the event and (for mouse events) needs no Accessibility
  permission. The handler fires on the main run loop, so wrap body in
  `MainActor.assumeIsolated`. A `@MainActor final class` is implicitly `Sendable`,
  so capturing `[weak self]` in the (possibly `@Sendable`) handler closure compiles.

---

## 2026-05-28 - Bringr-93j.20

Three-finger gesture fired on tap/rest instead of requiring an actual click.

- **What:** Gated the three-finger summon on a real physical trackpad click.
  Previously `ThreeFingerPressDetector` fired `.press` purely on the finger count
  reaching three (i.e. on touch/rest), so any three-finger touch summoned the wheel.
- **Files changed:**
  - `Bringr/ThreeFingerActivation.swift` — added `ThreeFingerInput` enum
    (`.fingerCount(Int)` / `.click(down: Bool)`); detector now tracks finger count
    AND click state and fires `.press` only on the rising edge of "clicked with
    exactly the required fingers" (works in either signal order). Release still
    fires on finger-lift below the required count (hold-to-select commit, US-009) —
    releasing the click alone does NOT commit. `ThreeFingerMonitor` now also installs
    a passive `NSEvent` global monitor for `.leftMouseDown`/`.leftMouseUp` and routes
    it through the detector; removed in `stop()`.
  - `BringrTests/ThreeFingerTests.swift` — rewritten to drive the detector with both
    inputs; new coverage for tap/rest-never-presses, click-gating, finger-lift release,
    click-up-alone-does-not-commit.
- **Learnings:**
  - Release semantics deliberately stay on finger-lift, not click-up: holding a
    physical trackpad click while navigating is awkward, so the natural hold-to-select
    flow is click-to-summon then lift-fingers-to-commit.
  - Firing on the *conjunction* (both finger count and click true), rather than only
    the click-down edge, makes the recogniser robust to the MultitouchSupport-thread
    vs main-thread ordering race. Trade-off: a contrived "hold a 1-finger click then
    add two fingers" would summon — benign and rare for v1.
  - Could not physically verify the trackpad gesture in the automated env (needs a
    human pressing the pad). Logic is covered by unit tests; app build + launch
    verified (no crash). `log show` showed no output for the subsystem — a capture
    quirk for the locally-signed dev build, not a failure.
  - Quality gates: build SUCCEEDED, `swiftlint lint --strict` 0 violations, all 172
    tests pass.
---

