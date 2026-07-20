import ComposableArchitecture
import Foundation
import SharedModels

/// Owns the queue of downloads: accepting new URLs, capping how many run
/// concurrently, and starting the next queued item whenever a slot frees up.
@Reducer
public struct DownloadQueueFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var items: IdentifiedArrayOf<DownloadItem.State> = []
    public var maxConcurrentDownloads: Int = 3

    public init(items: IdentifiedArrayOf<DownloadItem.State> = [], maxConcurrentDownloads: Int = 3) {
      self.items = items
      self.maxConcurrentDownloads = maxConcurrentDownloads
    }

    /// Strictly items transferring bytes right now, for tray display.
    public var downloadingCount: Int {
      items.reduce(into: 0) { count, item in
        if item.status.isDownloading { count += 1 }
      }
    }

    /// The average progress across items currently transferring, or `nil` if none.
    public var overallFractionCompleted: Double? {
      let runningFractions = items.compactMap { item -> Double? in
        guard case let .downloading(fractionCompleted) = item.status else { return nil }
        return fractionCompleted
      }
      guard !runningFractions.isEmpty else { return nil }
      return runningFractions.reduce(0, +) / Double(runningFractions.count)
    }
  }

  public enum Action: Sendable {
    case addURLs([URL])
    case items(IdentifiedActionOf<DownloadItem>)
  }

  public init() {}

  @Dependency(\.uuid) var uuid

  public var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .addURLs(urls):
        for url in urls {
          state.items.append(DownloadItem.State(id: uuid(), sourceURL: url))
        }
        return .merge(startQueuedItemsIfPossible(&state))

      case .items(.element(_, action: .moveResponse(_))),
        .items(.element(_, action: .downloadEvent(.failed(_)))),
        .items(.element(_, action: .cancelButtonTapped)):
        // A slot may have freed up; try to fill it.
        return .merge(startQueuedItemsIfPossible(&state))

      case .items:
        return .none
      }
    }
    .forEach(\.items, action: \.items) {
      DownloadItem()
    }
  }

  /// Starts as many `.queued` items as fit under `maxConcurrentDownloads`, given how
  /// many are already running. Uses a local counter rather than re-reading `state`
  /// mid-loop, since the `.start` effects it returns haven't executed yet.
  private func startQueuedItemsIfPossible(_ state: inout State) -> [Effect<Action>] {
    var runningCount = state.downloadingCount
    var effects: [Effect<Action>] = []
    for id in state.items.ids {
      guard runningCount < state.maxConcurrentDownloads else { break }
      guard state.items[id: id]?.status == .queued else { continue }
      effects.append(.send(.items(.element(id: id, action: .start))))
      runningCount += 1
    }
    return effects
  }
}
