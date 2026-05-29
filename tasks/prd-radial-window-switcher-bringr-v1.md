# PRD: Radial Window Switcher (PieSwitcher v1)

## Overview
PieSwitcher's single job in v1 is to switch fast between multiple windows of the **same** app without touching the keyboard. The user summons a radial (pie) menu at the cursor; it shows the apps that currently have open windows; hovering an app reveals a sub-wheel of that app's windows; hovering a window isolates it on screen for visual confirmation; clicking brings it forward and focuses it. The whole flow stays in the wheel — no Cmd-Tab, Mission Control, or Dock guessing.

This document covers v1 only. URLs, files, folders, custom commands, real window previews, user-created menus, and animations are explicitly future work, but the architecture must not foreclose them.

## Goals
- Summon-to-visible latency feels instant (target < 16 ms from trigger to first frame; menu window pre-warmed, never allocated on the hot path).
- Two activation methods work globally: simultaneous left+right mouse click, and three-finger trackpad press.
- Hovering an app isolates that app's windows; hovering a window isolates that single window — via a user-chosen reveal strategy.
- Selecting a window raises and focuses it, then fully restores the prior state of every other window/app.
- PieSwitcher remembers the last window chosen per app and pre-highlights it next time.
- The menu is data-driven and nestable (no singletons), so future menus and deeper trees drop in without a rewrite.
- No animations in v1.

## Quality Gates

These commands must pass for every user story:
- `xcodebuild -project PieSwitcher.xcodeproj -scheme PieSwitcher -configuration Debug -derivedDataPath build build` — must end in `** BUILD SUCCEEDED **`
- `swiftlint lint --strict` — zero violations
- `xcodebuild test -project PieSwitcher.xcodeproj -scheme PieSwitcher -destination 'platform=macOS'` — all tests pass

For UI/interaction stories, also include:
- Build and run the app (`pkill -x PieSwitcher 2>/dev/null; open build/Build/Products/Debug/PieSwitcher.app`) and verify the behavior visually, since native menu/overlay behavior cannot be fully unit-tested.

## User Stories

### US-001: Stand up lint and test tooling
As a developer, I want SwiftLint and an XCTest target wired into the project so that the quality gates can run from story one.

**Acceptance Criteria:**
- [ ] A unit-test target is added to `PieSwitcher.xcodeproj` and contains at least one passing sample test.
- [ ] `xcodebuild test -project PieSwitcher.xcodeproj -scheme PieSwitcher -destination 'platform=macOS'` runs and passes.
- [ ] SwiftLint is integrated (build plugin or invoked binary) with a committed `.swiftlint.yml`.
- [ ] `swiftlint lint --strict` runs clean against the current source.
- [ ] The three quality-gate commands are documented in the README or CLAUDE.md.

### US-002: Accessibility permission bootstrap
As a user, I want PieSwitcher to detect and request Accessibility/Input-Monitoring permission so that it can enumerate and control windows and observe global input.

**Acceptance Criteria:**
- [ ] On launch, the app checks `AXIsProcessTrusted()` and reflects the current state.
- [ ] If untrusted, the app prompts the user and links to the relevant System Settings pane.
- [ ] Preferences shows current permission status and a "re-check" action.
- [ ] When permission is missing, activation features degrade gracefully (no crash) and surface a clear message.
- [ ] Permission state changes are picked up without requiring a manual relaunch where the OS allows it.

### US-003: Window enumeration service
As the menu, I want a service that reports which apps currently have on-screen windows and the windows belonging to each so that the wheel reflects live state at summon time.

**Acceptance Criteria:**
- [ ] Returns running apps that own at least one normal, on-screen window.
- [ ] Returns per-app window list with a stable identifier, title, and owning app.
- [ ] Excludes PieSwitcher itself and apps with no normal windows (e.g. agents, menu-bar-only apps).
- [ ] Enumeration is invoked fresh on each summon and completes fast enough not to delay the menu (measure and record the timing).
- [ ] Logic is covered by unit tests using injected fixtures (no live system dependency in tests).

### US-004: Window control primitives
As the menu, I want primitives to raise/focus a window, hide and restore other apps, and hide and restore other windows of one app so that reveal strategies and selection can be built on them.

**Acceptance Criteria:**
- [ ] Can raise a specific window and move focus to it (target app activated, window made main/front).
- [ ] Can hide all apps except a target app, and restore them to their prior state.
- [ ] Can hide all windows of an app except a target window, and restore them.
- [ ] Captures prior z-order/visibility before mutating so it can be restored exactly.
- [ ] A restore call after any sequence returns windows/apps to their pre-summon visibility and ordering.

### US-005: Nestable, non-singleton menu model
As a developer, I want a tree-based menu model with dynamic node providers so that future menus, deeper nesting, and new action types are additive rather than rewrites.

**Acceptance Criteria:**
- [ ] A `MenuNode` tree supports child nodes to arbitrary depth.
- [ ] Node content can be static or supplied by a dynamic provider (e.g. "running apps", "windows of app X").
- [ ] A node carries an action (v1 actions: expand-to-children, focus-window); the action set is open for extension.
- [ ] No global/singleton menu instance — a menu is an instantiable definition resolved by a registry keyed on its trigger.
- [ ] Unit tests build the apps→windows tree from enumeration fixtures and assert structure.

### US-006: Overlay window and radial layout
As a user, I want the wheel to appear instantly at my cursor with evenly placed slices so that interaction is immediate and predictable.

**Acceptance Criteria:**
- [ ] A borderless, transparent, floating, click-through-safe overlay window is pre-warmed at launch and shown/hidden rather than recreated.
- [ ] Given N items, slices are laid out evenly around the ring with computed geometry.
- [ ] Hit-testing maps a cursor position to the correct slice (or "none" in the dead zone/outside).
- [ ] v1 slice content is placeholder: app icon/name for app slices; index number and/or title for window slices (no live preview).
- [ ] The overlay appears on the display under the cursor and is positioned at the cursor.
- [ ] No animations. Slice geometry and hit-testing are unit-tested; appearance is verified by build & run.

### US-007: Activation — simultaneous left+right mouse click
As a mouse user, I want pressing left and right buttons together to summon the menu so that I can trigger it without the keyboard.

**Acceptance Criteria:**
- [ ] A global event tap detects left and right button presses occurring within a small configurable threshold as a single "summon" trigger.
- [ ] Normal single left/right clicks pass through unaffected when the combo is not detected.
- [ ] The menu summons at the current cursor position.
- [ ] The trigger does not leak/duplicate events to the focused app.
- [ ] Threshold and detection logic are unit-tested in isolation from the live event stream.

### US-008: Activation — three-finger trackpad press
As a trackpad user, I want a three-finger press to summon the menu so that I can trigger it without a mouse or keyboard.

**Acceptance Criteria:**
- [ ] A three-finger trackpad press summons the menu at the cursor.
- [ ] Two-finger and single-finger gestures are unaffected.
- [ ] If the required multitouch detection is unavailable on the host, the app fails safe (no crash) and the limitation is logged/surfaced.
- [ ] Detectable, host-independent parts of the gesture logic are unit-tested; end-to-end behavior is verified by build & run.

### US-009: Interaction modes — hold-to-select and click-to-stay
As a user, I want to choose whether the menu stays open after I release the trigger so that it fits how I like to work.

**Acceptance Criteria:**
- [ ] Hold-to-select: the menu stays open while the trigger is held; releasing over a slice selects it; releasing in the dead zone cancels.
- [ ] Click-to-stay: the menu opens and remains after release; a click selects; a click outside or Esc cancels.
- [ ] The active mode is configurable and persisted.
- [ ] Both modes drive the same selection/cancel paths (no divergent behavior beyond open/persist semantics).
- [ ] The mode state machine is unit-tested.

### US-010: App-hover — isolate app and open window sub-wheel
As a user, I want hovering an app to push the other apps out of the way and reveal that app's windows so that I can drill into the right app.

**Acceptance Criteria:**
- [ ] Hovering an app slice applies the chosen reveal strategy to every non-target app.
- [ ] A level-2 sub-wheel opens showing exactly the hovered app's windows from the enumeration service.
- [ ] Moving to a different app re-targets the isolation and rebuilds the sub-wheel.
- [ ] Moving back out restores the other apps.
- [ ] Nesting uses the US-005 tree (no special-cased two-level hack).

### US-011: Window-hover — isolate a single window
As a user, I want hovering a window slice to leave only that window visible so that I get instant visual confirmation before committing.

**Acceptance Criteria:**
- [ ] Hovering a window slice applies the chosen reveal strategy to every other window of the same app, leaving only the target visible.
- [ ] Moving between window slices re-isolates the new target.
- [ ] Moving away from all window slices restores the app's other windows.
- [ ] v1 uses placeholder slice content (number/title), not a captured preview image.

### US-012: Select and commit — focus and remember
As a user, I want clicking/releasing on a window to bring it forward and have PieSwitcher remember my choice so that the next summon starts from where I left off.

**Acceptance Criteria:**
- [ ] Committing a window raises it, activates its app, and moves focus to it.
- [ ] All previously hidden apps/windows are restored to their pre-summon state after commit.
- [ ] The chosen window is persisted as the last selection for that app (best-effort match by app + window title/order across restarts).
- [ ] On the next summon, the remembered window for an app is pre-highlighted when present.
- [ ] Persistence and pre-highlight selection logic are unit-tested.

### US-013: Reveal-strategy setting
As a user, I want to choose how "other" windows/apps get out of the way so that the behavior matches my preference.

**Acceptance Criteria:**
- [ ] Preferences offers two reveal strategies: raise-target-to-front and hide-others.
- [ ] The chosen strategy applies to both the app-hover (US-010) and window-hover (US-011) levels.
- [ ] Both strategies are fully implemented and selectable.
- [ ] The setting is persisted and takes effect on the next summon without relaunch.
- [ ] A sensible default is set and documented.

### US-014: Appearance customization
As a user, I want to customize the wheel's appearance so that it fits my taste and screen.

**Acceptance Criteria:**
- [ ] Preferences exposes appearance options: overall size/radius, slice fill/opacity, and label visibility.
- [ ] Changes persist and apply on the next summon.
- [ ] Changing appearance never breaks slice geometry or hit-testing.
- [ ] Appearance changes are verified by build & run.

### US-015: Cancel and guaranteed state restoration
As a user, I want every way of backing out to leave my windows exactly as they were so that PieSwitcher never strands a hidden window.

**Acceptance Criteria:**
- [ ] Esc, click-outside, release-in-dead-zone, and trigger-loss all cancel cleanly.
- [ ] After any cancel path, every hidden app/window is restored to its pre-summon visibility and z-order.
- [ ] If the app crashes or the menu is force-dismissed mid-reveal, no window remains hidden after relaunch (restore-on-launch safety net).
- [ ] Restoration is exercised by unit tests over the state machine and verified by build & run.

## Functional Requirements
- FR-1: The system must summon the radial menu at the cursor on simultaneous left+right mouse press.
- FR-2: The system must summon the radial menu at the cursor on a three-finger trackpad press.
- FR-3: The top-level wheel must list only apps that currently have on-screen, normal windows, computed fresh at each summon.
- FR-4: Hovering an app slice must open a sub-wheel listing that app's current windows.
- FR-5: Hovering an app slice must apply the configured reveal strategy to all non-target apps.
- FR-6: Hovering a window slice must apply the configured reveal strategy to all other windows of that app, leaving only the target visible.
- FR-7: Committing a window slice must raise it, activate its app, and move focus to it.
- FR-8: After commit or any cancel, the system must restore all hidden apps/windows to their pre-summon visibility and ordering.
- FR-9: The system must persist and pre-highlight the last selected window per app.
- FR-10: The system must support hold-to-select and click-to-stay modes, configurable and persisted.
- FR-11: The system must offer two reveal strategies (raise, hide-others), configurable, persisted, applied at both menu levels.
- FR-12: The system must offer appearance customization (size, slice fill/opacity, label visibility), persisted.
- FR-13: The menu must be represented as an instantiable, nestable tree with dynamic providers and no singleton menu instance.
- FR-14: The overlay window must be pre-warmed and reused so summon does not allocate it on the hot path.
- FR-15: The system must request and reflect Accessibility/Input-Monitoring permission and degrade gracefully without it.
- FR-16: The system must not play animations in v1.

## Non-Goals (Out of Scope)
- Live/captured window preview thumbnails (requires Screen Recording permission) — future; v1 uses placeholders.
- URL, file, folder, and custom-command actions — future (model must allow them, but none ship in v1).
- A UI for users to create/edit custom menus or to manually place/order apps in the wheel — future; v1 auto-detects and auto-lays-out.
- Customizable shortcuts/gestures per menu beyond the two fixed v1 triggers — future.
- Animations and animation settings — future.
- Switching between windows of *different* apps as the primary goal (v1 supports cross-app navigation only as a side effect of the apps wheel; the product focus is same-app windows).
- Cross-restart preview fidelity or exact window-id persistence (v1 remembers by best-effort match).

## Technical Considerations
- Window enumeration/control relies on the Accessibility API (AXUIElement) plus CoreGraphics window listing; this gates US-003/US-004 on US-002.
- Global L+R detection uses a CGEventTap; three-finger detection likely requires the private MultitouchSupport framework or an NSTouch-based approach — this is the highest-risk item (see Open Questions) and is isolated in US-008.
- "Instant" budget: keep the overlay window allocated and hidden; do enumeration lazily but measure it; never block the main thread on AX calls longer than necessary. Reveal effects happen on hover, not on summon, so summon stays cheap.
- Restoration must capture pre-summon z-order/visibility before any mutation; prefer reversible strategies and add a restore-on-launch safety net (US-015).
- Settings stories (US-013/US-014) extend the existing Preferences window described in CLAUDE.md rather than introducing new windows.
- Default reveal strategy should match the described experience (only the target visible) while respecting the performance goal; pick and document the default in US-013.

## Success Metrics
- Summon-to-first-frame latency meets the instant target on a typical machine.
- Selecting a window focuses the correct window on the first try in manual testing across Chrome/Ghostty/Telegram/Mail with multiple windows.
- After 20 summon/cancel/commit cycles, no window is left hidden or mis-ordered.
- Both reveal strategies and both interaction modes are selectable and behave as specified.
- Quality gates (build, lint, tests) pass on every story.

## Open Questions
- Three-finger press: is "press" a physical click or a tap, and is the private MultitouchSupport framework acceptable for v1, or should we ship mouse-only first and fast-follow the trackpad?
- Reveal default: ship with hide-others (matches the described "everything else disappears") or raise-to-front (most performant/reversible)?
- "Remember the choice": match remembered windows by title, by order, or both, when window ids change across app restarts?
- Multi-monitor: for v1, is covering only the display under the cursor sufficient, or must app/window isolation span all displays?