import AppKit
import ComposableArchitecture
import Foundation

/// Opens a downloaded file, or reveals it in Finder. Wrapped as a dependency so
/// `HistoryFeature`'s reducer logic stays testable without touching `NSWorkspace`.
@DependencyClient
public struct FileActionsClient: Sendable {
  public var openFile: @Sendable (_ fileURL: URL) -> Void
  public var revealInFinder: @Sendable (_ fileURL: URL) -> Void
}

extension FileActionsClient: DependencyKey {
  public static let liveValue = FileActionsClient(
    openFile: { fileURL in
      NSWorkspace.shared.open(fileURL)
    },
    revealInFinder: { fileURL in
      NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
  )
}

extension DependencyValues {
  public var fileActionsClient: FileActionsClient {
    get { self[FileActionsClient.self] }
    set { self[FileActionsClient.self] = newValue }
  }
}
