import Foundation

/// The lifecycle of a single item in the download queue.
public enum DownloadStatus: Equatable, Sendable {
  case queued
  case downloading(fractionCompleted: Double)
  case finished(fileURL: URL)
  case failed(message: String)
  case cancelled

  /// Counts against the concurrency cap: still waiting for a slot, or occupying one.
  public var countsTowardConcurrencyLimit: Bool {
    switch self {
    case .downloading, .queued: true
    case .finished, .failed, .cancelled: false
    }
  }

  /// Strictly "actively transferring bytes right now", for tray display purposes.
  public var isDownloading: Bool {
    if case .downloading = self { return true }
    return false
  }

  public var isFinished: Bool {
    switch self {
    case .finished, .failed, .cancelled: true
    case .downloading, .queued: false
    }
  }

  public var fractionCompleted: Double? {
    switch self {
    case let .downloading(fractionCompleted):
      fractionCompleted
    case .finished:
      1
    case .queued, .failed, .cancelled:
      nil
    }
  }
}
