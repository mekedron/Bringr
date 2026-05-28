# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

### project.pbxproj is hand-written with sequential hex IDs
- Object IDs follow `1A00000000000000000000XX` where `XX` is hex, assigned in order. Highest used so far: `0x20`. Continue the sequence for new objects.
- Adding a **source file** to a target requires editing 4 spots: `PBXFileReference`, `PBXBuildFile`, the owning `PBXGroup`'s `children`, and the target's `PBXSourcesBuildPhase` `files`. There is no Xcode GUI doing this for you here.
- After editing, sanity-check with `xcodebuild -list -project Bringr.xcodeproj` (parses the project; lists targets/schemes).

### Unit testing setup
- Test target `BringrTests` is **host-based**: `TEST_HOST = $(BUILT_PRODUCTS_DIR)/Bringr.app/Contents/MacOS/Bringr`, `BUNDLE_LOADER = $(TEST_HOST)`, plus a `PBXTargetDependency` on the app. `ENABLE_TESTABILITY = YES` is set at project Debug level, so `@testable import Bringr` works.
- To make an app type reachable from tests, keep it `internal` (the default). `private` members are NOT visible even via `@testable` — e.g. `AboutView()` is uncallable from tests because a private stored property makes its memberwise init private.
- The test target is wired into the shared scheme's `<Testables>` (else `xcodebuild test` finds nothing to run).
- **GOTCHA for US-007/US-008:** `xcodebuild test` launches the host app (Bringr.app) to inject the bundle. Once app launch installs a global `CGEventTap` / MultitouchSupport observer, guard it so it does NOT run under XCTest (check env var `XCTestConfigurationFilePath` or `NSClassFromString("XCTest")`), or tests may hang or trigger Accessibility/Input-Monitoring permission prompts.

### Quality gates (run all three before "done")
- Build: `xcodebuild -project Bringr.xcodeproj -scheme Bringr -configuration Debug -derivedDataPath build build`
- Lint: `swiftlint lint --strict` (binary from `brew install swiftlint`; config `.swiftlint.yml` uses `included: [Bringr, BringrTests]` so it never scans `build/`). `--strict` turns warnings into failures.
- Test: `xcodebuild test -project Bringr.xcodeproj -scheme Bringr -destination 'platform=macOS'`

### App lifecycle, @MainActor services, and launch bootstrap
- `AppDelegate` (`Bringr/AppDelegate.swift`) is the launch-time bootstrap home, wired via `@NSApplicationDelegateAdaptor(AppDelegate.self)` in `BringrApp`. It owns app-lifetime services and is where future overlay pre-warm (US-006) and event taps (US-007/008) belong. There is no clean pure-SwiftUI "on launch once" hook for a MenuBarExtra-only app.
- **Concurrency gotcha:** a `@MainActor` `ObservableObject` service cannot be a default-initialized stored property of a *non*-isolated `NSObject` (its init is main-actor isolated). Fix: mark the owning `AppDelegate` `@MainActor` too. App delegates run on the main actor anyway.
- **Concurrency gotcha:** static helpers used as **default closure arguments** (`init(probe: () -> Bool = Self.systemFoo)`) must be `nonisolated`, else "Converting `@MainActor () -> X` ... loses global actor" (warning in Swift 5, error in Swift 6).
- **Testability seam:** wrap live system calls (`AXIsProcessTrusted`, prompts, `NSWorkspace.open`) in injectable closures with live-impl defaults. Tests construct the service with fixture closures — no real permission state, no system dialogs. See `PermissionsManager`.
- **XCTest launch guard (the US-001 gotcha, now concrete):** `AppDelegate.applicationDidFinishLaunching` early-returns when `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`. `xcodebuild test` launches Bringr.app to host the bundle; without this guard the launch-time AX prompt pops a system dialog / hangs the run. Reuse this exact guard for the event tap (US-007) and multitouch observer (US-008).
- **Sharing a service across AppDelegate + SwiftUI scenes:** the delegate creates the instance; scenes read it via `appDelegate.permissions` and inject with `.environmentObject(...)` (or pass to a `@ObservedObject` init param, as `MenuContent` does). One instance, observed live.

### Adding a Preferences/settings window
- Mirror the existing About `Window` scene: `Window("Bringr Preferences", id: "preferences")` + a menu `Button` calling `openWindow(id: "preferences")` after `NSApp.activate(ignoringOtherApps: true)`. Works for `LSUIElement` apps. Later settings stories (US-009/013/014) add sections to `PreferencesView`, not new windows.

### Window/app control behind an injectable seam (the US-004 pattern)
- The PermissionsManager injectable-closure pattern generalizes to a **protocol seam** for anything that touches live system state. `WindowControlling` (a `@MainActor protocol`) is the seam: `WindowController` (orchestration) is unit-tested against an in-memory `FakeWindowSystem`; `LiveWindowSystem` (AX + NSRunningApplication) is the production conformer. Tests never construct `LiveWindowSystem`, so no AX calls / permission prompts during `xcodebuild test`.
- **Identity types** for windows/apps: `AppID { pid }` and `WindowID { app; token }`, both `Hashable, Sendable`. `token` is opaque (live system uses enumeration index for now). US-003's enumeration service can refine `token` later — `WindowController` only relies on `Hashable`, so it's additive. Don't over-commit US-004 to an ID scheme US-003 owns.
- **Capture-before-mutate / restore-to-baseline**: capture the pre-mutation state of the touched scope (app visibility+frontmost, or one app's window minimized-state+order) **exactly once per session** (guard flags: `didCaptureApps`, `windowBaseline[app] == nil`). `restore()` replays the captured baseline, NOT the inverse of each mutation — this is why re-targeting (hover app A → app B → A) restores correctly: incremental "undo what I did" breaks under re-targeting, baseline-replay doesn't. Restore order: unhide apps → un-minimize + re-raise windows (back-to-front so original front ends on top) → activate original frontmost last.
- **Hiding one window**: AX has no "hide window"; `kAXMinimizedAttribute = true` is the only reversible per-window hide. `restore()` un-minimizes. (OS minimize animation is system behavior, unrelated to the PRD's "no wheel animations".)
- **Live AX boilerplate that works under strict build** (no bridging header, no private API): app element via `AXUIElementCreateApplication(pid)`; windows via `AXUIElementCopyAttributeValue(_, kAXWindowsAttribute as CFString, &v)` then `v as? [AXUIElement]`; read bool attrs with `value as? Bool`; set bools with `kCFBooleanTrue/kCFBooleanFalse` (NOT `true as CFBoolean`); raise via `AXUIElementPerformAction(el, kAXRaiseAction as CFString)`; focus via setting `kAXMainAttribute` + `kAXFocusedAttribute`. kAX* constants import as `String`. AX symbols link with just `import ApplicationServices` (no explicit framework).
- **Same @MainActor-default-arg gotcha as before, non-closure form**: `init(system: WindowControlling = LiveWindowSystem())` fails ("Call to main actor-isolated initializer in a synchronous nonisolated context"). Fix: `init(system: WindowControlling? = nil) { self.system = system ?? LiveWindowSystem() }` — construct inside the `@MainActor` init body.
- **Verification limitation**: US-004 ships primitives with no runtime driver yet (no trigger/overlay until US-006/007/010), so "build & run verify visually" only confirms the app still launches stably with the new code linked. The live AX primitives get interactive verification when a trigger exists; orchestration is proven by the fake-backed tests now.

---

## 2026-05-28 - Bringr-93j.1 (US-001: lint and test tooling)
- Added `BringrTests` XCTest target to `Bringr.xcodeproj` (host-based on `Bringr.app`) with one passing sample test (`testToolingIsWiredUp`) that exercises `@testable import Bringr`.
- Wired the test target into the shared `Bringr` scheme `<Testables>`.
- Installed SwiftLint via Homebrew (0.63.3) and added `.swiftlint.yml` scoped to `Bringr`/`BringrTests`.
- Documented the three quality-gate commands in `README.md`.
- Files changed: `Bringr.xcodeproj/project.pbxproj`, `Bringr.xcodeproj/xcshareddata/xcschemes/Bringr.xcscheme`, `BringrTests/BringrTests.swift` (new), `.swiftlint.yml` (new), `README.md`.
- All three gates pass: build SUCCEEDED, swiftlint 0 violations, 1 test passed.
- **Learnings:** see Codebase Patterns above — hand-written pbxproj editing, host-based test target, `@testable` visibility caveat, and the future event-tap-under-XCTest gotcha.
---

## 2026-05-28 - Bringr-93j.2 (US-002: Accessibility permission bootstrap)
- Added `PermissionsManager` (`@MainActor ObservableObject`): reads `AXIsProcessTrusted()` via an injectable `probe`, plus injectable `promptForAccess` (`AXIsProcessTrustedWithOptions` system dialog) and `openSettings` (opens `x-apple.systempreferences:...?Privacy_Accessibility`). Exposes `isTrusted`, `status` (`PermissionStatus` enum → title/detail/symbol), `recheck()`, and `startMonitoring()`/`stopMonitoring()` (DistributedNotificationCenter `com.apple.accessibility.api` + 1s poll → AC #5 live pickup).
- Added `AppDelegate` (wired via `@NSApplicationDelegateAdaptor`): on launch checks trust, prompts if untrusted, starts monitoring — all guarded out under XCTest.
- Added `PreferencesView` (new `Window` scene + "Preferences…" menu item, ⌘,): shows status + "Re-check" + "Open System Settings". `MenuContent` now shows a "Grant Accessibility Access…" warning item while untrusted.
- 7 unit tests in `PermissionsManagerTests` (status mapping, recheck pickup, prompt/openSettings invocation, message presence). All 8 tests pass.
- Files changed: `Bringr/PermissionsManager.swift` (new), `Bringr/AppDelegate.swift` (new), `Bringr/PreferencesView.swift` (new), `Bringr/BringrApp.swift`, `BringrTests/PermissionsManagerTests.swift` (new), `Bringr.xcodeproj/project.pbxproj` (IDs 0x21–0x28).
- Gates: build SUCCEEDED, swiftlint 0 violations, 8 tests pass. App launches stably (no crash) whether trusted or not.
- **Verification caveat:** confirmed the app launches and stays alive via CLI; the menu → Preferences → Re-check click-through was NOT exercised interactively (needs GUI access). Geometry/logic is unit-tested; visual click-through is the one unverified slice.
- **Learnings:** see the two new Codebase Patterns sections above (app lifecycle / @MainActor service concurrency / XCTest launch guard, and adding a Preferences window).
---

## 2026-05-28 - Bringr-93j.4 (US-004: Window control primitives)
- Added `WindowControl.swift` (app target): identity types `AppID`/`WindowID`; `WindowControlling` `@MainActor` protocol (the seam); `WindowController` orchestrator with primitives `raiseAndFocus(_:)` (AC1), `hideOtherApps(besides:)` (AC2), `hideOtherWindows(besides:)` (AC3), per-scope capture-once baseline (AC4), and `restore()` replaying the baseline (AC5); `LiveWindowSystem` conformer over NSRunningApplication + Accessibility API.
- Added `WindowControlTests.swift` (test target): in-memory `FakeWindowSystem` modeling app/window visibility + z-order, and 7 tests covering all 5 ACs incl. target reveal-then-restore (app + window) and restore-to-baseline-despite-re-targeting (proves capture-once).
- Files changed: `Bringr/WindowControl.swift` (new), `BringrTests/WindowControlTests.swift` (new), `Bringr.xcodeproj/project.pbxproj` (IDs 0x29–0x2C).
- Gates: build SUCCEEDED, swiftlint 0 violations, 15 tests pass (7 new). App launches stably with the new code linked.
- Not wired into `AppDelegate` yet — nothing drives the primitives until a trigger/overlay (US-006/007/010); avoided an unused stored property. The protocol seam means a future enumeration service (US-003) or trigger can inject/drive it.
- **Learnings:** see the new "Window/app control behind an injectable seam" Codebase Patterns section above.
---

