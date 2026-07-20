import ComposableArchitecture
import Foundation

/// Progress/outcome events for a single in-flight download.
public enum DownloadEvent: Equatable, Sendable {
  case progress(fractionCompleted: Double)
  case finished(temporaryFileURL: URL, suggestedFileName: String, byteCount: Int64)
  case failed(message: String)
}

/// Downloads a URL to a staged temporary location, reporting progress along the way,
/// and separately relocates a staged file into `~/Downloads` with a unique name.
/// Split into two steps so the queue reducer can decide the final file name (and
/// de-duplicate) independently of the network transfer.
@DependencyClient
public struct DownloadClient: Sendable {
  public var events: @Sendable (_ url: URL) -> AsyncStream<DownloadEvent> = { _ in .finished }
  public var moveToDownloads: @Sendable (_ temporaryFileURL: URL, _ suggestedFileName: String) throws -> URL
}

extension DownloadClient: DependencyKey {
  public static let liveValue = DownloadClient(
    events: { url in
      AsyncStream { continuation in
        let delegate = DownloadSessionDelegate(continuation: continuation)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        continuation.onTermination = { _ in
          task.cancel()
          session.finishTasksAndInvalidate()
        }
        task.resume()
      }
    },
    moveToDownloads: { temporaryFileURL, suggestedFileName in
      let downloadsFolder = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask)[0]
      let destination = try uniqueDestination(for: suggestedFileName, in: downloadsFolder)
      try FileManager.default.moveItem(at: temporaryFileURL, to: destination)
      return destination
    }
  )
}

extension DependencyValues {
  public var downloadClient: DownloadClient {
    get { self[DownloadClient.self] }
    set { self[DownloadClient.self] = newValue }
  }
}

/// Appends " 2", " 3", … before the extension until the name doesn't collide with an
/// existing file, mirroring how Finder/Safari resolve naming conflicts.
private func uniqueDestination(for fileName: String, in folder: URL) throws -> URL {
  let baseName = (fileName as NSString).deletingPathExtension
  let fileExtension = (fileName as NSString).pathExtension
  var candidate = folder.appendingPathComponent(fileName)
  var attempt = 2
  while FileManager.default.fileExists(atPath: candidate.path) {
    let numberedName =
      fileExtension.isEmpty
      ? "\(baseName) \(attempt)"
      : "\(baseName) \(attempt).\(fileExtension)"
    candidate = folder.appendingPathComponent(numberedName)
    attempt += 1
  }
  return candidate
}

/// `URLSessionDownloadDelegate` only guarantees the downloaded file exists at
/// `location` for the duration of the delegate callback, so it must be moved
/// somewhere durable immediately rather than referenced later.
private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let continuation: AsyncStream<DownloadEvent>.Continuation

  init(continuation: AsyncStream<DownloadEvent>.Continuation) {
    self.continuation = continuation
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    continuation.yield(
      .progress(fractionCompleted: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    )
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let suggestedFileName = downloadTask.response?.suggestedFilename ?? location.lastPathComponent
    let byteCount = downloadTask.countOfBytesReceived
    let stagedURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(location.pathExtension)
    do {
      try FileManager.default.moveItem(at: location, to: stagedURL)
      continuation.yield(
        .finished(temporaryFileURL: stagedURL, suggestedFileName: suggestedFileName, byteCount: byteCount)
      )
    } catch {
      continuation.yield(.failed(message: error.localizedDescription))
    }
    continuation.finish()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
    continuation.yield(.failed(message: error.localizedDescription))
    continuation.finish()
  }
}
