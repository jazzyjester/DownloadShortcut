import Foundation

/// User-configurable preferences, persisted via `@Shared(.appStorage)`.
public struct AppSettings: Equatable, Codable, Sendable {
  public var maxConcurrentDownloads: Int
  public var launchAtLogin: Bool
  public var notifyOnCompletion: Bool
  public var playSoundOnCompletion: Bool
  public var maxHistoryItems: Int
  /// When enabled, pressing the global shortcut skips the quick-add popup entirely
  /// and starts downloading immediately if the clipboard already contains a valid
  /// URL — falling back to the popup when it doesn't.
  public var autoDownloadWhenClipboardHasValidURL: Bool

  public init(
    maxConcurrentDownloads: Int = 3,
    launchAtLogin: Bool = false,
    notifyOnCompletion: Bool = true,
    playSoundOnCompletion: Bool = false,
    maxHistoryItems: Int = 10,
    autoDownloadWhenClipboardHasValidURL: Bool = false
  ) {
    self.maxConcurrentDownloads = maxConcurrentDownloads
    self.launchAtLogin = launchAtLogin
    self.notifyOnCompletion = notifyOnCompletion
    self.playSoundOnCompletion = playSoundOnCompletion
    self.maxHistoryItems = maxHistoryItems
    self.autoDownloadWhenClipboardHasValidURL = autoDownloadWhenClipboardHasValidURL
  }

  public static let `default` = AppSettings()
}
