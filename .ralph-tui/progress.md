# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

- **Adding a source/test file = 4 pbxproj edits.** `Bringr.xcodeproj/project.pbxproj` is hand-managed with sequential `1A0000000000000000000NN` UUIDs (NOT file-system-synchronized groups), so a new file needs: (1) a `PBXBuildFile` entry, (2) a `PBXFileReference` entry, (3) an entry in the `BringrTests`/`Bringr` `PBXGroup` `children`, (4) an entry in the target's `PBXSourcesBuildPhase` `files`. Pick two fresh UUIDs above the current max (`grep -oE '1A0000000000000000000[0-9A-F]+' ... | sort -u | tail`). fileRef + buildFile are distinct UUIDs.
- **SwiftLint caps file length at 400 and type-body at 250** (`swiftlint lint --strict`, the gate). When a test file outgrows it, split by concern into a new file (e.g. `RadialNavigatorCommitTests.swift` for US-012) following the existing one-story-per-file naming — don't relax the config.
- **Pure-core / thin-shell + injected fakes.** State machines and navigators (`RadialNavigator`, `InteractionStateMachine`, `WindowController`) hold no AppKit window; they take seam protocols (`WindowControlling`, `WindowEnumerationSource`) so the whole policy is unit-tested against `FakeWindowSystem` (in WindowControlTests) and `StubEnumerationSource` (in MenuModelTests), both module-internal and reused across test files.
- **Stores take injectable `UserDefaults`.** `LastSelectionStore` / `InteractionMode.current(from:)` accept defaults so tests use an ephemeral suite, never `.standard`. Tear it down Sendable-cleanly by capturing only the suite *string*: `addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }`.
- **SourceKit single-file diagnostics lie.** "Cannot find type X" / "No such module 'XCTest'" from in-editor indexing are cross-file artifacts; trust `xcodebuild` for ground truth.

---

## 2026-05-28 - Bringr-93j.12 (US-012: Select and commit — focus and remember)

- Finalized the commit + remember + pre-highlight flow. The implementation already existed (scaffolded during US-011) but carried two `// needs to be reimagined/refactored` markers and had no tests at the navigator/primitive level. Reviewed it — the design is correct as-is — so I removed the markers and added the missing coverage rather than rewriting.
- **Files changed:**
  - `Bringr/WindowControl.swift` — removed the stale US-012 marker on `commit(_:)`. The primitive restores everything else first, then un-minimizes + raises + focuses the target (restore re-activates the prior frontmost app, so it must run *before* the raise or it steals focus back).
  - `Bringr/RadialNavigator.swift` — removed the stale US-012 marker on `commit(_:)`. It guards for a level-1 window leaf, remembers `(appName, title, index)`, delegates to `windowControl.commit`, clears state, returns the `WindowID` (nil for app slice / dead zone so the controller cancel-restores).
  - `BringrTests/WindowControlTests.swift` — +3 tests for `WindowController.commit` (restore-then-focus; un-minimize a pre-minimized target; no-session still raises/focuses).
  - `BringrTests/RadialNavigatorCommitTests.swift` — **new file** (+10 tests) for navigator commit + pre-highlight, with its own fake-backed fixture and an ephemeral store. Registered in the pbxproj.
  - `Bringr.xcodeproj/project.pbxproj` — 4 edits to add the new test file (UUIDs 0057/0058).
- AC5 coverage now spans three layers: `WindowMemoryTests` (store persistence + pure `matchIndex`), `RadialNavigatorCommitTests` (navigator remember-on-commit + set-prehighlight-on-expand, incl. AC3→AC4 round trip), `WindowControlTests` (the focus/restore primitive).
- Gates: build SUCCEEDED, `swiftlint --strict` 0 violations (31 files), `xcodebuild test` 144 tests / 0 failures. App launches and runs clean.
- **Learnings:**
  - The commit path's ordering is load-bearing: `restore()` re-activates the pre-summon frontmost app as its *last* step, so committing must restore **before** raise/focus, else the chosen window loses focus immediately.
  - Pre-highlight is purely visual (AC4) — it never auto-commits. Committing always requires the cursor to actually resolve to the window slice; `RadialNavigator.commit` reads the live region's index, not `expandedWindowIndex`, so it's robust to hover lag at release time.
  - `RadialNavigator.expandApp` already reads the store on every app-hover (for pre-highlight), so any test that hovers an app touches the injected store — inject an ephemeral one in fixtures or `.standard` leaks in.
  - Adding tests can trip the SwiftLint length gate even when the app builds; split into a per-story test file rather than relaxing the rule (see Codebase Patterns).

---

