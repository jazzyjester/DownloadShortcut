import ApplicationServices
import AppKit
import ComposableArchitecture
import CoreGraphics

/// Reads text off the system pasteboard. Wrapped as a dependency so features that
/// need clipboard access stay testable without touching real AppKit state.
@DependencyClient
public struct ClipboardClient: Sendable {
  /// Before reading, tries to simulate ⌘C to capture whatever's currently *selected*
  /// in the frontmost app, even if the user never explicitly copied it — falling back
  /// to whatever's already on the pasteboard if that's not possible (no Accessibility
  /// permission, nothing selected, or the frontmost app doesn't support copy).
  public var readString: @Sendable () async -> String? = { nil }
  /// Prompts for Accessibility permission (needed for `readString`'s synthetic ⌘C) if
  /// it hasn't been granted or denied yet. Safe to call unconditionally at launch —
  /// a no-op once the user has already answered the system prompt.
  public var requestAccessibilityAuthorizationIfNeeded: @Sendable () -> Void = {}
}

extension ClipboardClient: DependencyKey {
  public static let liveValue = ClipboardClient(
    readString: {
      await copySelectionIfPossibleThenReadPasteboard()
    },
    requestAccessibilityAuthorizationIfNeeded: {
      // Using the documented raw key ("AXTrustedCheckOptionPrompt") rather than the
      // `kAXTrustedCheckOptionPrompt` C global: that global isn't `Sendable` under
      // Swift 6 strict concurrency, and its value is a stable, published API contract.
      let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
    }
  )
}

/// Simulates ⌘C in the frontmost app before reading the pasteboard, so pressing the
/// shortcut after merely *selecting* text (never copying it) still picks it up.
/// Posting a synthetic keystroke into another app requires Accessibility permission;
/// without it — or if nothing was selected, or the app ignores copy — this silently
/// falls back to whatever was already on the pasteboard, exactly like before this
/// feature existed.
private func copySelectionIfPossibleThenReadPasteboard() async -> String? {
  let pasteboard = NSPasteboard.general

  if AXIsProcessTrusted() {
    let changeCountBeforeCopy = pasteboard.changeCount
    postCommandCKeystroke()
    // Apps vary in how long they take to respond to the synthetic ⌘C and write to
    // the pasteboard; poll briefly rather than guessing a single fixed delay.
    for _ in 0..<15 {
      if pasteboard.changeCount != changeCountBeforeCopy { break }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  return pasteboard.string(forType: .string)
}

private func postCommandCKeystroke() {
  let virtualKeyC: CGKeyCode = 0x08
  guard let eventSource = CGEventSource(stateID: .combinedSessionState) else { return }
  let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKeyC, keyDown: true)
  let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKeyC, keyDown: false)
  keyDown?.flags = .maskCommand
  keyUp?.flags = .maskCommand
  keyDown?.post(tap: .cghidEventTap)
  keyUp?.post(tap: .cghidEventTap)
}

extension DependencyValues {
  public var clipboardClient: ClipboardClient {
    get { self[ClipboardClient.self] }
    set { self[ClipboardClient.self] = newValue }
  }
}
