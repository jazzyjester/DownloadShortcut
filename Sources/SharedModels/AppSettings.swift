import Foundation

/// User-configurable preferences, persisted via `@Shared(.appStorage)`.
public struct AppSettings: Equatable, Codable, Sendable {
  public var maxConcurrentDownloads: Int
  public var launchAtLogin: Bool
  public var notifyOnCompletion: Bool
  public var playSoundOnCompletion: Bool
  public var maxHistoryItems: Int

  public init(
    maxConcurrentDownloads: Int = 3,
    launchAtLogin: Bool = false,
    notifyOnCompletion: Bool = true,
    playSoundOnCompletion: Bool = false,
    maxHistoryItems: Int = 10
  ) {
    self.maxConcurrentDownloads = maxConcurrentDownloads
    self.launchAtLogin = launchAtLogin
    self.notifyOnCompletion = notifyOnCompletion
    self.playSoundOnCompletion = playSoundOnCompletion
    self.maxHistoryItems = maxHistoryItems
  }

  public static let `default` = AppSettings()
}
