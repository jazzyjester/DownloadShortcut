import ComposableArchitecture
import Foundation
import SharedModels

/// Persists `AppSettings` as JSON in Application Support, mirroring `HistoryClient`'s
/// approach rather than `@Shared(.appStorage)` — keeps this package's dependency
/// surface small and the persistence behavior easy to reason about/test directly.
@DependencyClient
public struct SettingsClient: Sendable {
  public var load: @Sendable () -> AppSettings = { .default }
  public var save: @Sendable (_ settings: AppSettings) throws -> Void
}

extension SettingsClient: DependencyKey {
  public static let liveValue: Self = {
    let fileURL = Self.settingsFileURL()
    return Self(
      load: {
        guard let data = try? Data(contentsOf: fileURL) else { return .default }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .default
      },
      save: { settings in
        let data = try JSONEncoder().encode(settings)
        try data.write(to: fileURL, options: .atomic)
      }
    )
  }()

  private static func settingsFileURL() -> URL {
    let appSupport = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DownloadShortcut", isDirectory: true)
    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    return appSupport.appendingPathComponent("settings.json")
  }
}

extension DependencyValues {
  public var settingsClient: SettingsClient {
    get { self[SettingsClient.self] }
    set { self[SettingsClient.self] = newValue }
  }
}
