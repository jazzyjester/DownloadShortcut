# DownloadShortcut

A quick-download menu bar app for macOS. Press a global keyboard shortcut anywhere on
the system, a small box pops up near your cursor pre-filled with the last thing you
copied, hit Enter, and it downloads straight to `~/Downloads` — with a live progress
ring in the menu bar and a history of recent downloads one click away.

## Features

- **Global shortcut, anywhere**: configurable in Settings (default ⌥⌘V).
- **Clipboard-aware popup**: the edit box appears at your mouse cursor, pre-filled with
  the last copied text. Paste/type one URL, or several on separate lines to queue them
  all at once.
- **Live tray progress**: the menu bar icon turns into a circular progress ring with a
  percentage while downloads are active, and briefly flashes done when finished.
- **Download queue**: several downloads can run concurrently (default 3 at a time,
  configurable); extras wait their turn.
- **History menu**: click the tray icon to see recent downloads, each with "Open" and
  "Show in Finder"; cancel an in-flight download or clear history.
- **Settings**: change the global shortcut, max concurrent downloads, launch-at-login,
  and completion notification/sound.

## Project structure

Business logic (all TCA reducers, effects, and dependency clients) lives in a plain
Swift package under `Sources/`, fully unit-tested and buildable with the Swift
toolchain alone — no Xcode required:

```
swift build
swift test
```

> **Only have Xcode Command Line Tools, not full Xcode?** `swift test` needs Swift
> Testing's runtime framework, which lives outside the default search path when Xcode
> itself isn't installed. If you hit `no such module 'Testing'` or a `dlopen` failure
> for `Testing.framework`, run:
> ```
> swift test \
>   -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
>   -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
>   -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
>   -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
> ```
> With full Xcode installed, plain `swift test` works with no extra flags.

The `App/` directory holds the thin AppKit "shell" — the status bar item, the popup
panel, window/entitlements/Info.plist glue — that needs a real macOS GUI session and
Xcode to build and run. It's generated into an `.xcodeproj` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) rather than hand- or Xcode-edited, so
the project file stays diffable and reproducible:

```
brew install xcodegen   # if you don't have it
xcodegen generate
open DownloadShortcut.xcodeproj
```

Then build & run the `DownloadShortcut` scheme in Xcode.

## Dependencies

- [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) — app architecture.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey capture and recorder UI.
  Pinned below 1.16.0 in `Package.swift`: newer releases use the `#Preview` macro,
  which needs Xcode's PreviewsMacros plugin and won't build with only Command Line
  Tools. Bump this once you've confirmed a build against full Xcode.

## Distribution

This app is built for direct (non–App Store) distribution: sign with a Developer ID
and notarize before sharing. It is **not sandboxed**, which keeps global hotkeys and
writing to `~/Downloads` simple with no extra entitlements or security-scoped
bookmarks.

## Requirements

- macOS 14 Sonoma or later
- Swift 6 toolchain
- Xcode (for building/running the app shell; the `Sources/` package builds without it)
