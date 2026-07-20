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
  public var shortcutTriggered: @Sendable () -> AsyncStream<Void> = { .finished }
}

extension HotkeyClient: DependencyKey {
  public static let liveValue = HotkeyClient(
    shortcutTriggered: {
      AsyncStream { continuation in
        // `KeyboardShortcuts` has no API to unregister a single handler; this is
        // fine in practice because the app registers exactly one long-lived
        // listener for the lifetime of the process.
        KeyboardShortcuts.onKeyUp(for: .quickDownload) {
          continuation.yield()
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
