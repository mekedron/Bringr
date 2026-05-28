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
- **A global NSEvent monitor never fires for events routed to your own app.**
  `addGlobalMonitorForEvents` only sees events sent to *other* apps; events the
  window server delivers to your own window (e.g. cursor moves over the
  non-activating overlay once a held trigger is released) reach it via
  `addLocalMonitorForEvents` instead. To track input that may land in either place,
  install BOTH — they're mutually exclusive per event (each event reaches exactly
  one app), so there's no double-counting; have the local handler `return event` so
  it passes through. Installs go through the injectable `EventMonitorInstaller` seam
  (`.live` in production) so the wiring is unit-testable without a live event stream.
- **New `.swift` files must be added to `Bringr.xcodeproj/project.pbxproj` by hand**
  — the project has no `PBXFileSystemSynchronizedRootGroup`, so a file created on
  disk is silently *not* compiled (a new test class "executes 0 tests" and the build
  still succeeds). Add four entries, mirroring an existing same-target file: a
  `PBXBuildFile`, a `PBXFileReference`, a child in the target's `PBXGroup`, and an
  entry in its `PBXSourcesBuildPhase`. IDs follow `1A00…00XX`; pick the next free
  pair above the current max (grep the IDs). `pbxproj` uses tab indentation.

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

## 2026-05-28 - Bringr-93j.19

Hover feedback died after switching the interaction mode to click-to-stay.

- **What:** The pie menu's hover (slice highlight + app/window isolation) was driven
  by a single *global* NSEvent monitor. In hold-to-select the held chord keeps the
  app underneath active, so cursor moves arrive there (as drags) and the global
  monitor fires. In click-to-stay the trigger is released and the moves are
  delivered to our own overlay — a global monitor never sees those, so hover went
  dead the moment the wheel persisted. Added a *local* monitor for the same hover
  mask alongside the global one (the two are mutually exclusive per event), set
  `acceptsMouseMovedEvents = true` on the overlay, and left the dismiss monitor
  global-only (a local mouse-down monitor would double-handle the SwiftUI click
  gesture as a cancel).
- **Files changed:**
  - `Bringr/RadialMenuWindow.swift` — `acceptsMouseMovedEvents = true` on the panel;
    new `EventMonitorInstaller` seam (`.live` wraps NSEvent's global/local/remove);
    `RadialMenuController` takes a `monitorInstaller` (default `.live`);
    `startMenuMonitors()` now installs global + local hover monitors through it and
    `stopMenuMonitors()` removes through it. WHY comments explain the global-vs-local
    split and why dismiss stays global-only.
  - `BringrTests/RadialMenuControllerHoverTests.swift` (new) — injects a recording
    `EventMonitorInstaller`; asserts both a global and a local hover monitor are wired
    in BOTH modes (the regression catcher), the local hover monitor passes events
    through, dismiss is global-only, and dismiss removes every installed monitor.
  - `Bringr.xcodeproj/project.pbxproj` — registered the new test file with the
    BringrTests target (4 entries, IDs `…0065`/`…0066`).
- **Learnings:**
  - The bug was purely in the live monitor layer; `updateHover` itself is
    mode-agnostic. A unit test calling `updateHover` directly would pass before and
    after the fix and catch nothing — the *wiring* (which monitors get installed) is
    what had to be covered, hence the injectable installer + recorder.
  - Could not physically perform the chord/gesture and sweep the cursor over slices
    in the automated env, so mode-independent hover is covered by the wiring tests;
    app build + launch verified (no crash).
  - Hit the silent "new file not in the target" trap: the first full test run
    *succeeded* with the new file ignored; `-only-testing` on the new class reported
    "Executed 0 tests", which is the tell. See the new pbxproj pattern up top.
  - Quality gates: build SUCCEEDED, `swiftlint lint --strict` 0 violations, all 177
    tests pass (was 173 before the 4 new ones).
---

