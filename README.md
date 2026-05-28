# Bringr

A focused radial / pie-menu app launcher and window manager for macOS.

> Status: early scaffold. The current build does nothing more than place a status-bar icon and an About window. Real functionality lands in the next iteration.

## Why another one?

There are already plenty of radial launchers on macOS — Launchy, Pieoneer, OrbitRing, Kando, DockDoor, Dock, Exposé, DockView, and so on. They all try to do *everything*: open files, fire URLs, run scripts, switch windows, paste snippets, control music. That's fine, but for me it dilutes the one thing I actually want from this kind of tool.

Bringr's first and only job is:

**Switch fast between multiple windows of the same app, without touching the keyboard.**

That's it. Files, folders, URLs, custom commands — maybe later. Not now.

## The core interaction

1. Summon the pie menu (hotkey or trackpad gesture — TBD).
2. The wheel shows the apps that currently have open windows.
3. Hover an app — say Google Chrome — and everything that isn't Chrome fades away. A sub-wheel appears with one slice per Chrome window, each with a live preview.
4. Hover a window slice — every other window in that app hides too, leaving only the one under the cursor on screen. Quick visual confirmation.
5. Click — that window comes forward, focus follows, and Bringr remembers the choice for next time.

The whole flow stays in the wheel. No Cmd-Tab, no Mission Control, no clicking around the Dock guessing which Chrome window has the tab you wanted.

## What's out of scope (for now)

- Opening files / folders
- Launching URLs
- Custom commands and scripts
- Clipboard, snippets, anything text-based

These may show up later as opt-in modules, but they're explicitly *not* part of v1. The point is to do one thing well first.

## Stack

- Pure Swift, latest toolchain
- SwiftUI + AppKit interop where needed (status bar, window enumeration, screen capture for previews)
- Xcode project — open `Bringr.xcodeproj` and hit Run

## Building

```sh
xcodebuild -project Bringr.xcodeproj -scheme Bringr -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/Bringr.app
```

Or just open the project in Xcode and press ⌘R.

## Quality gates

All three commands must pass before any change is considered done:

```sh
# 1. Compile — must end in "** BUILD SUCCEEDED **"
xcodebuild -project Bringr.xcodeproj -scheme Bringr -configuration Debug -derivedDataPath build build

# 2. Lint — must report zero violations (warnings fail under --strict)
swiftlint lint --strict

# 3. Test — all XCTest cases must pass
xcodebuild test -project Bringr.xcodeproj -scheme Bringr -destination 'platform=macOS'
```

SwiftLint is a separate binary; install it with `brew install swiftlint`. Its
rules live in [`.swiftlint.yml`](.swiftlint.yml). Unit tests live in the
`BringrTests` target (a host-based bundle loaded into `Bringr.app`).

## Repository

<https://github.com/mekedron/Bringr>
