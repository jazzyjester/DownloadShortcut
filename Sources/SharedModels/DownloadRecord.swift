import Foundation

/// A completed (or failed) download, persisted to disk for the History menu.
public struct DownloadRecord: Identifiable, Equatable, Codable, Sendable {
  public var id: UUID
  public var sourceURL: URL
  public var fileName: String
  public var savedFileURL: URL?
  public var byteCount: Int64?
  public var completedAt: Date
  public var didFail: Bool

  public init(
    id: UUID = UUID(),
    sourceURL: URL,
    fileName: String,
    savedFileURL: URL? = nil,
    byteCount: Int64? = nil,
    completedAt: Date,
    didFail: Bool = false
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.fileName = fileName
    self.savedFileURL = savedFileURL
    self.byteCount = byteCount
    self.completedAt = completedAt
    self.didFail = didFail
  }
}
