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

