import AppKit
import ClipboardClient
import ComposableArchitecture
// `KeyboardShortcuts.Name` predates Swift 6 strict concurrency and isn't marked
// `Sendable`, though it's an immutable value type and safe to share; `@preconcurrency`
// downgrades that mismatch to a warning instead of an error.
@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  /// The single global shortcut this app registers: pop up the quick-add box.
  public static let quickDownload = Self(
    "quickDownload",
    default: .init(.v, modifiers: [.command, .option])
  )
}

/// Bridges the `KeyboardShortcuts` library's global hotkey callback into an
/// `AsyncStream`, so reducers can `for await` shortcut presses without importing
/// AppKit/Carbon directly.
@DependencyClient
public struct HotkeyClient: Sendable {
  /// Yields the text to seed the popup with each time the shortcut fires — captured
  /// via `ClipboardClient.readString()` (which may itself simulate ⌘C to grab a
  /// selection that was never explicitly copied).
  public var shortcutTriggered: @Sendable () -> AsyncStream<String?> = { .finished }
}

extension HotkeyClient: DependencyKey {
  public static let liveValue = HotkeyClient(
    shortcutTriggered: {
      AsyncStream { continuation in
        // `KeyboardShortcuts` has no API to unregister a single handler; this is
        // fine in practice because the app registers exactly one long-lived
        // listener for the lifetime of the process.
        KeyboardShortcuts.onKeyUp(for: .quickDownload) {
          print(
            "[HotkeyClient] shortcut fired, frontmost app before capture = "
              + "\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")"
          )
          Task { @MainActor in
            @Dependency(\.clipboardClient) var clipboardClient
            // Must happen *before* activating this app below: `readString()` may
            // simulate ⌘C to capture a selection the user never explicitly copied,
            // and that synthetic keystroke is delivered to whichever app is
            // frontmost/key at the moment it's posted. Once we activate ourselves,
            // it would be delivered to us instead of the app the user actually had
            // something selected in.
            let seedText = await clipboardClient.readString()
            print(
              "[HotkeyClient] capture done, frontmost app now = "
                + "\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"), "
                + "seedText length = \(seedText?.count ?? -1)"
            )

            // Then activate as soon as possible after that — since macOS is more
            // willing to grant real key/focus status to an activation request made
            // close to the actual input event than one issued several async hops
            // (and run loop turns) later, deep inside a reducer's response to it.
            // `.accessory` apps can also have activation requests silently ignored
            // regardless of timing, so switch to `.regular` too (`QuickAddPanel`
            // switches back to `.accessory` once the popup is dismissed).
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            continuation.yield(seedText)
          }
        }
      }
    }
  )
}

extension DependencyValues {
  public var hotkeyClient: HotkeyClient {
    get { self[HotkeyClient.self] }
    set { self[HotkeyClient.self] = newValue }
  }
}
