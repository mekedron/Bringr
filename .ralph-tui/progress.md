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
- **When a bead says "add SPM package X", prefer wrapping the Apple framework it
  thinly wraps.** This is an `.xcodeproj` with no SPM dependencies and no GUI an agent
  can drive; adding a remote package also makes the build network-dependent (the build
  gate fails offline). For thin wrappers (e.g. LaunchAtLogin-Modern → `SMAppService`),
  call the system API directly inside an injectable `ObservableObject` (the
  `PermissionsManager` shape: `@Published private(set)` state + injected
  probe/action closures, `nonisolated static` live impls) so the logic is unit-tested
  without touching real system state. Don't credit a package you didn't bundle.
- **Per-summon settings share one shape; push them through the same seam.** A setting
  that changes a *future* summon (interaction mode, appearance, reveal strategy) is a
  `String`-raw `CaseIterable enum` with `static default` / `defaultsKey` /
  `current(from:)`, surfaced in Preferences via `@AppStorage(key)` and read in
  `RadialMenuController.summon` through an injected `provider` closure (default
  `{ X.current() }`), then pushed into the navigator/`WindowController` *before*
  `navigator.open(...)` — never mid-session, so a Preferences change can't switch
  behaviour halfway through a reveal. To add one, copy `RevealStrategy` + its
  `strategyProvider` wiring.
- **Two `CGEventTap`s at `.headInsertEventTap` run newest-first; to suppress an event
  before another tap buffers it, create your tap *last*.** The mouse-chord tap holds a
  lone `leftMouseDown` for ~120 ms then replays it (leaking it to the app behind). The
  three-finger click tap must therefore be created *after* the chord tap so it sits at
  the head and *consumes* the three-finger click before the chord tap can buffer it.
  Enforce the order everywhere the taps are (re)started — launch wiring AND the
  `permissions.$isTrusted` retry sink both do `chord.start()` then `trackpad.start()`.
  A tap is transparent when it returns `passUnretained(event)`, so the three-finger tap
  only consumes when 3 fingers are actually down; a 0-finger mouse click passes straight
  through to the chord tap. **Only an active tap can consume; a passive
  `addGlobalMonitorForEvents` cannot** — so suppression needs Accessibility permission.
  Keep the passive monitor as a permission-free *fallback* (summon works, no
  suppression) and upgrade it to the tap on permission grant by re-calling `start()`.
- **A visual side effect that needs its own AppKit window goes behind a protocol seam,
  like `EventMonitorInstaller`/`PermissionsManager`.** `Dimming` (show/clear) is injected
  into `WindowController`; production wires `LiveDimmer` (a reused click-through `NSPanel`),
  tests wire a recording `FakeDimmer` and assert the calls — so the strategy *dispatch* is
  unit-tested while the live panel is verified only by build & run. When the tested core
  needs live geometry (window frames for the dim cutout), add it to the existing
  `WindowControlling` protocol (`frame(of:)`) rather than reaching into AppKit from the core.

---

## 2026-05-28 - Bringr-93j.23

Three-finger click should suppress other trackpad gestures while it opens the menu.

- **Research finding (the bead asked to investigate feasibility first):**
  - The only *real* leak today is the triggering **click** itself. The three-finger
    click was detected by a *passive* `NSEvent` global monitor that can't consume, so
    the `leftMouseDown` reached the app behind — and the mouse-chord tap actually
    *buffers + replays* that lone left-click ~120 ms later, so the app behind got a
    genuine stray click. Fixed by detecting the click with an active `CGEventTap` that
    swallows it.
  - WindowServer multi-finger gestures (Mission Control, App Exposé, swipe-between-
    pages) are interpreted *below* the event-tap layer and are **not** userspace-
    suppressible. But they need a *swipe*, not a stationary *click*, so a real three-
    finger press never triggers them (the bead author's own intuition). Documented, not
    "fixed" — there's nothing to fix.
  - Two-finger gestures (scroll/magnify) can't physically co-occur with three fingers
    down, so suppressing them would guard a scenario that can't happen — deliberately
    NOT added (would be over-engineering + taxes every scroll tick).
- **What:** `ThreeFingerPressDetector` gained a pure `handleClick(down:) -> (reaction,
  suppress)`: a mouse-down is swallowed exactly when it completes a press, and the
  matching up iff its down was (no unbalanced click to the app behind). The live
  `ThreeFingerMonitor` now detects the click via an active `CGEventTap` (mirrors
  `MouseChordMonitor`) instead of the passive monitor, consuming the three-finger
  click. Kept the passive monitor as a permission-free fallback (summon works, no
  suppression); `start()` upgrades fallback → tap and is re-called on permission grant.
- **Files changed:**
  - `Bringr/ThreeFingerActivation.swift` — `clickSuppressed` state + `handleClick`
    on the detector; live class split into `startMultitouch()` + `installClickPath()`
    (`installClickTap`/`installClickFallbackMonitor`), new `handleTap` consume logic,
    `import CoreGraphics`, expanded `stop()`. Class doc records the research findings.
  - `Bringr/AppDelegate.swift` — `$isTrusted` retry sink now starts chord THEN trackpad
    (ordering matters, see the new pattern up top).
  - `BringrTests/ThreeFingerTests.swift` — 6 new tests (down+up suppressed, ordinary/
    two-finger not suppressed, up swallowed after fingers lift, interleave leak edge,
    reset clears suppression). 17 → 23 in the class.
- **Learnings:**
  - Two head-inserted taps run newest-first — see the new tap-ordering pattern at the
    top. This is the load-bearing insight; get the start order wrong and the chord tap
    eats the three-finger click.
  - Switching the click path to a tap means three-finger suppression needs Accessibility
    permission (the passive monitor was permission-free). Preserved permission-free
    *summon* via the fallback so this isn't a regression; only suppression waits for
    permission.
  - Couldn't physically three-finger-click in the automated env. The consume *decision*
    is fully unit-tested (the pure `handleClick`); the live tap consume + the two-tap
    ordering need a human to verify on a real trackpad (three-finger-click over a button
    in another app → the button must NOT fire). App build + launch verified (no crash).
  - Quality gates: build SUCCEEDED, `swiftlint lint --strict` 0 violations, all 206
    tests pass (was 200; +6, confirmed via `-only-testing:BringrTests/ThreeFingerTests`
    → 23 run).
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

## 2026-05-28 - Bringr-toj

Added a "Launch at login" option to Preferences.

- **What:** New `LaunchAtLoginManager` (an `ObservableObject` mirroring
  `PermissionsManager`'s injected-system-call pattern) backed by
  `SMAppService.mainApp` — the same modern API the LaunchAtLogin-Modern SPM
  package wraps, no legacy helper bundle. `setEnabled(_:)` registers/unregisters
  and then republishes the *actual* system status (so a failed call can't make the
  toggle lie); `refresh()` re-reads status to catch approvals/removals made in
  System Settings. A "Startup" section with the toggle was added to
  `PreferencesView`, the manager is owned by `AppDelegate` and injected as an
  environment object on the Preferences window.
- **Decision — direct SMAppService instead of the SPM package:** the bead suggested
  adding LaunchAtLogin-Modern via Xcode's "Add Package Dependencies" GUI. Done
  directly against `SMAppService` instead because (a) an agent can't drive the Xcode
  package UI, (b) it would be the project's *only* SPM dependency, making the build
  network-dependent (the build gate would fail offline), and (c) the package is a
  ~30-line `SMAppService` wrapper. User-facing behavior and the acceptance criteria
  (which name SMAppService explicitly) are identical. Left `AboutView` unchanged — no
  third-party package is bundled, so there's nothing to credit.
- **Files changed:**
  - `Bringr/LaunchAtLogin.swift` (new) — `LaunchAtLoginManager`.
  - `BringrTests/LaunchAtLoginTests.swift` (new) — 7 tests over the manager logic
    using a `registered`-backed fake probe/register/unregister trio.
  - `Bringr/PreferencesView.swift` — "Startup" section + toggle, `@EnvironmentObject`,
    `#Preview` updated, window height 560 → 620.
  - `Bringr/AppDelegate.swift` — owns `launchAtLogin`.
  - `Bringr/BringrApp.swift` — injects it into the Preferences window.
  - `Bringr.xcodeproj/project.pbxproj` — registered both new files (IDs `…0067`/`…0068`
    for the source, `…0069`/`…006A` for the test).
- **Learnings:**
  - `SMAppService.mainApp` works for a non-sandboxed `LSUIElement` app with no
    entitlement; `import ServiceManagement` auto-links the framework (no Frameworks
    build-phase entry needed). Registration persistence across reboot is OS behavior
    and can't be exercised in the automated env; the manager logic is unit-tested and
    app build + launch verified (no crash). Toggle-click → real registration needs
    manual verification (and the ad-hoc dev signature can make `register()` throw on
    *this* machine specifically — handled gracefully).
  - **Concurrent-iteration pbxproj hazard:** another iteration added
    `WindowActivationShim.m` to the same pbxproj mid-task and grabbed the exact next
    free ID pair (`…0067`/`…0068`) I'd picked, producing duplicate object IDs and a
    "project is damaged / `-[PBXFileReference buildPhase]: unrecognized selector`"
    failure. A formatter then auto-renumbered the shim to `…006B`/`…006C`, clearing it.
    Tell: re-grep ALL pbxproj IDs *immediately before* editing, and after a build
    failure check `grep '… = {isa' | uniq -d` for duplicate *definitions* (plain
    `uniq -d` over every ID match is useless — each ID legitimately recurs).
  - Quality gates: build SUCCEEDED, `swiftlint lint --strict` 0 violations, all 184
    tests pass (was 177; +7 new). Confirmed the new class executes via
    `-only-testing:BringrTests/LaunchAtLoginTests` (7 run) to dodge the silent
    "0 tests" trap.
---

## 2026-05-28 - Bringr-93j.13

US-013: reveal-strategy setting — let the user choose how "other" apps/windows get
out of the way (raise-to-front / hide-others / dim-others).

- **What:** Added `RevealStrategy` (default `hideOthers`), persisted and read fresh
  per summon exactly like `InteractionMode`/`RadialAppearance`. `WindowController` now
  dispatches the active strategy onto its primitives at BOTH levels via
  `revealApp(_:)` / `revealWindow(_:)` — the navigator's two reveal call sites switched
  to these from `hideOtherApps`/`hideOtherWindows`:
  - raise = activate target app / AX-raise target window, hide nothing;
  - hide = the existing minimize/hide behaviour (still the default);
  - dim = raise the target + a spotlight overlay (`Dimming` seam → `LiveDimmer`) that
    darkens the desktop with the target window(s) cut out. `restore()` clears the dim;
    `restoreWindows(of:)` re-cuts it to the app's windows when leaving the sub-wheel.
  Added a "Reveal" radio-group section to Preferences; `RadialMenuController` reads a
  `strategyProvider` at summon and pushes it via `navigator.setRevealStrategy`.
- **Files changed:**
  - `Bringr/RevealStrategy.swift` (new) — enum + persistence (mirrors `InteractionMode`).
  - `Bringr/Dimming.swift` (new) — `Dimming` protocol + `LiveDimmer` (reused click-through
    `NSPanel` just below `.floating`, even-odd `NSBezierPath` cutout fill).
  - `Bringr/WindowControl.swift` — `frame(of:)` on the protocol; `strategy`/`dimmer`
    state; `setStrategy`, `revealApp`/`revealWindow` dispatch + raise/dim impls; dim-aware
    `restoreWindows`/`restore`.
  - `Bringr/LiveWindowSystem.swift` — `frame(of:)` via AX position/size → AppKit-global flip.
  - `Bringr/RadialNavigator.swift` — `setRevealStrategy`; the two reveal calls renamed.
  - `Bringr/RadialMenuWindow.swift` — `strategyProvider`, pushed in `summon`.
  - `Bringr/PreferencesView.swift` — "Reveal" picker; window height 620 → 720.
  - `Bringr/AppDelegate.swift` — inject `LiveDimmer` into the production `WindowController`.
  - `BringrTests/FakeWindowSystem.swift` — `frame(of:)` + `frames` fixture; recording `FakeDimmer`.
  - `BringrTests/RevealStrategyTests.swift` (new) — 16 tests (8 persistence, 8 dispatch).
  - `Bringr.xcodeproj/project.pbxproj` — registered 3 new files (IDs `…006D`–`…0072`).
- **Learnings:**
  - **Merge-under-you variant of the concurrent hazard:** the engine merged another
    iteration's app-commit work (new `RadialCommitResult`, `commit -> RadialCommitResult?`)
    into my working tree *between* my first reads and my edits — my mental model of
    `RadialNavigator`/`commit` was stale and an Edit failed "modified since read". Tell:
    `git diff HEAD -- <file>` shows ONLY your own hunks even though the file contains
    types you never wrote (they're already in HEAD). Re-read a file right before editing
    once a session has been running a while; don't trust an early read.
  - dim can't be a flat panel "between" same-level normal windows (window levels are
    global, so a panel above normal dims the target too). The working spotlight = a panel
    just below `.floating` covering the screen union, with the target frame(s) punched out
    and the target AX-raised so it fills the hole. No frame → empty holes = uniform dim
    (graceful; target is still raised, so it reads as frontmost).
  - AX `kAXPosition`/`kAXSize` are top-left/y-down off the primary screen; flip to AppKit
    via `primaryHeight - y - h` (`NSScreen.screens.first`). Untestable headlessly — a wrong
    flip misplaces the cutout but never fails a gate. The dim/raise visuals (and the hover
    sweep) need a human; the strategy *dispatch* (which ops fire, with what frames) is fully
    covered by the `FakeDimmer`-backed tests. Build + launch verified (no crash).
  - Quality gates: build SUCCEEDED, `swiftlint --strict` 0 violations, all 200 tests pass
    (16 new; confirmed via `-only-testing:BringrTests/RevealStrategyTests` → 16 run).
---

