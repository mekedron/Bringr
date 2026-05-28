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

