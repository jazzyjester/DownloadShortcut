import ComposableArchitecture
import Foundation

/// Drives what the menu bar icon looks like. Deliberately decoupled from
/// `DownloadQueueFeature`'s own types — the parent feature computes the primitives
/// (`activeCount`, `overallFraction`, a just-finished file name) and forwards them in,
/// so this reducer only owns icon *presentation* and the finished-flourish timing.
@Reducer
public struct StatusBarFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var phase: Phase = .idle

    public init(phase: Phase = .idle) {
      self.phase = phase
    }

    public enum Phase: Equatable, Sendable {
      case idle
      case downloading(activeCount: Int, overallFraction: Double)
      case justFinished(fileName: String)
    }
  }

  public enum Action: Sendable {
    case downloadQueueChanged(activeCount: Int, overallFraction: Double?, justFinishedFileName: String?)
    case justFinishedFlourishElapsed
  }

  public init() {}

  @Dependency(\.continuousClock) var clock
  private enum CancelID: Sendable { case flourish }

  public var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .downloadQueueChanged(activeCount, overallFraction, justFinishedFileName):
        if let justFinishedFileName {
          state.phase = .justFinished(fileName: justFinishedFileName)
          return .run { send in
            try await clock.sleep(for: .seconds(2))
            await send(.justFinishedFlourishElapsed)
          }
          .cancellable(id: CancelID.flourish, cancelInFlight: true)
        } else if activeCount > 0, let overallFraction {
          state.phase = .downloading(activeCount: activeCount, overallFraction: overallFraction)
          return .none
        } else {
          state.phase = .idle
          return .none
        }

      case .justFinishedFlourishElapsed:
        state.phase = .idle
        return .none
      }
    }
  }
}
