import ComposableArchitecture
import Foundation
import SharedModels

/// Persists download history as JSON in Application Support. Deliberately simple
/// file-based storage rather than a database, since this is a short bounded list.
@DependencyClient
public struct HistoryClient: Sendable {
  public var load: @Sendable () -> [DownloadRecord] = { [] }
  public var save: @Sendable (_ records: [DownloadRecord]) throws -> Void
}

extension HistoryClient: DependencyKey {
  public static let liveValue: Self = {
    let fileURL = Self.historyFileURL()
    return Self(
      load: {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.historyDecoder.decode([DownloadRecord].self, from: data)) ?? []
      },
      save: { records in
        let data = try JSONEncoder.historyEncoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
      }
    )
  }()

  private static func historyFileURL() -> URL {
    let appSupport = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DownloadShortcut", isDirectory: true)
    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    return appSupport.appendingPathComponent("history.json")
  }
}

extension DependencyValues {
  public var historyClient: HistoryClient {
    get { self[HistoryClient.self] }
    set { self[HistoryClient.self] = newValue }
  }
}

extension JSONEncoder {
  fileprivate static let historyEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

extension JSONDecoder {
  fileprivate static let historyDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
