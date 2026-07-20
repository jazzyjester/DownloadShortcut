import ComposableArchitecture
import FileActionsClient
import Foundation
import HistoryClient
import SharedModels

/// The list of recent downloads shown from the tray menu, with open/reveal/clear
/// actions. Persistence is owned by the parent (`AppFeature`) since it needs to run
/// after every mutation that touches `records`; this feature just reacts to taps.
@Reducer
public struct HistoryFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var records: [DownloadRecord] = []

    public init(records: [DownloadRecord] = []) {
      self.records = records
    }
  }

  public enum Action: Sendable {
    case clearHistoryButtonTapped
    case openButtonTapped(id: DownloadRecord.ID)
    case revealInFinderButtonTapped(id: DownloadRecord.ID)
  }

  public init() {}

  @Dependency(\.fileActionsClient) var fileActionsClient

  public var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .clearHistoryButtonTapped:
        state.records.removeAll()
        return .none

      case let .openButtonTapped(id):
        guard let fileURL = state.records.first(where: { $0.id == id })?.savedFileURL else { return .none }
        return .run { _ in fileActionsClient.openFile(fileURL) }

      case let .revealInFinderButtonTapped(id):
        guard let fileURL = state.records.first(where: { $0.id == id })?.savedFileURL else { return .none }
        return .run { _ in fileActionsClient.revealInFinder(fileURL) }
      }
    }
  }
}
