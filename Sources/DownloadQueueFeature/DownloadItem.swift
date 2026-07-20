import ComposableArchitecture
import DownloadClient
import Foundation
import SharedModels

/// A single queued/in-flight/completed download.
@Reducer
public struct DownloadItem: Sendable {
  @ObservableState
  public struct State: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceURL: URL
    public var status: DownloadStatus

    public init(id: UUID = UUID(), sourceURL: URL) {
      self.id = id
      self.sourceURL = sourceURL
      self.status = .queued
    }
  }

  public enum Action: Sendable {
    case cancelButtonTapped
    case downloadEvent(DownloadEvent)
    case moveResponse(Result<URL, DownloadItemError>)
    case start
  }

  public init() {}

  @Dependency(\.downloadClient) var downloadClient

  public var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .cancelButtonTapped:
        state.status = .cancelled
        return .cancel(id: CancelID.download(state.id))

      case let .downloadEvent(event):
        switch event {
        case let .progress(fractionCompleted):
          state.status = .downloading(fractionCompleted: fractionCompleted)
          return .none

        case let .finished(temporaryFileURL, suggestedFileName, _):
          return .run { send in
            await send(
              .moveResponse(
                Result {
                  try downloadClient.moveToDownloads(temporaryFileURL, suggestedFileName)
                }
                .mapError { DownloadItemError(message: $0.localizedDescription) }
              )
            )
          }

        case let .failed(message):
          state.status = .failed(message: message)
          return .none
        }

      case let .moveResponse(.success(savedFileURL)):
        state.status = .finished(fileURL: savedFileURL)
        return .none

      case let .moveResponse(.failure(error)):
        state.status = .failed(message: error.message)
        return .none

      case .start:
        state.status = .downloading(fractionCompleted: 0)
        return .run { [sourceURL = state.sourceURL] send in
          for await event in downloadClient.events(sourceURL) {
            await send(.downloadEvent(event))
          }
        }
        .cancellable(id: CancelID.download(state.id))
      }
    }
  }
}

/// `Result`/`Equatable` need a concrete `Error`-conforming type; `any Error` can't
/// conform to `Equatable` on its own.
public struct DownloadItemError: Error, Equatable, Sendable {
  public var message: String
}

extension DownloadItem {
  public enum CancelID: Hashable, Sendable {
    case download(UUID)
  }
}
