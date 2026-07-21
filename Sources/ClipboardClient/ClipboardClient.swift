import AppKit
import ComposableArchitecture

/// Reads text off the system pasteboard. Wrapped as a dependency so features that
/// need clipboard access stay testable without touching real AppKit state.
@DependencyClient
public struct ClipboardClient: Sendable {
  public var readString: @Sendable () -> String? = { nil }
}

extension ClipboardClient: DependencyKey {
  public static let liveValue = ClipboardClient(
    readString: {
      NSPasteboard.general.string(forType: .string)
    }
  )
}

extension DependencyValues {
  public var clipboardClient: ClipboardClient {
    get { self[ClipboardClient.self] }
    set { self[ClipboardClient.self] = newValue }
  }
}
