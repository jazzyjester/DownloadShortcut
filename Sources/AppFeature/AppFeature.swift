import ClipboardClient
import ComposableArchitecture
import DownloadQueueFeature
import FileActionsClient
import Foundation
import HistoryClient
import HistoryFeature
import HotkeyClient
import QuickAddFeature
import SettingsFeature
import SharedModels
import StatusBarFeature

/// The root feature: wires the download queue, history, settings, tray icon state,
/// and the quick-add popup together, and owns the cross-cutting effects (the global
/// hotkey subscription, recording finished downloads to history, completion feedback).
@Reducer
public struct AppFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var downloadQueue: DownloadQueueFeature.State
    public var history: HistoryFeature.State
    public var settings: SettingsFeature.State
    public var statusBar: StatusBarFeature.State
    @Presents public var quickAdd: QuickAddFeature.State?

    public init(
      downloadQueue: DownloadQueueFeature.State = .init(),
      history: HistoryFeature.State = .init(),
      settings: SettingsFeature.State = .init(),
      statusBar: StatusBarFeature.State = .init(),
      quickAdd: QuickAddFeature.State? = nil
    ) {
      self.downloadQueue = downloadQueue
      self.history = history
      self.settings = settings
      self.statusBar = statusBar
      self.quickAdd = quickAdd
    }
  }

  public enum Action: Sendable {
    case downloadQueue(DownloadQueueFeature.Action)
    case fileRevealRequested(URL)
    case history(HistoryFeature.Action)
    case historyLoaded([DownloadRecord])
    case hotkeyPressed
    case onLaunch
    case quickAdd(PresentationAction<QuickAddFeature.Action>)
    case settings(SettingsFeature.Action)
    case showQuickAddPopup
    case statusBar(StatusBarFeature.Action)
  }

  public init() {}

  @Dependency(\.clipboardClient) var clipboardClient
  @Dependency(\.completionFeedbackClient) var completionFeedbackClient
  @Dependency(\.date.now) var now
  @Dependency(\.fileActionsClient) var fileActionsClient
  @Dependency(\.historyClient) var historyClient
  @Dependency(\.hotkeyClient) var hotkeyClient

  public var body: some Reducer<State, Action> {
    Scope(state: \.downloadQueue, action: \.downloadQueue) {
      DownloadQueueFeature()
    }
    Scope(state: \.history, action: \.history) {
      HistoryFeature()
    }
    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }
    Scope(state: \.statusBar, action: \.statusBar) {
      StatusBarFeature()
    }
    Reduce { state, action in
      switch action {
      case let .downloadQueue(.items(.element(id, .moveResponse(.success(savedFileURL))))):
        return handleDownloadSettled(&state, id: id, savedFileURL: savedFileURL, isFailure: false)

      case let .downloadQueue(.items(.element(id, .downloadEvent(.failed(_))))):
        return handleDownloadSettled(&state, id: id, savedFileURL: nil, isFailure: true)

      case .downloadQueue:
        return refreshStatusBarEffect(state, justFinishedFileName: nil)

      case let .fileRevealRequested(fileURL):
        return .run { _ in fileActionsClient.revealInFinder(fileURL) }

      case .history:
        return .none

      case let .historyLoaded(records):
        state.history.records = records
        return .none

      case .hotkeyPressed:
        // Ignore repeat presses while the popup is already showing.
        guard state.quickAdd == nil else { return .none }
        guard state.settings.settings.autoDownloadWhenClipboardHasValidURL else {
          state.quickAdd = QuickAddFeature.State()
          return .none
        }
        // Auto-download mode: skip the popup entirely when the clipboard already has
        // a usable URL, falling back to the popup (so the user can fix it up) when
        // it doesn't.
        return .run { send in
          if let text = await clipboardClient.readString(), let url = QuickAddFeature.extractURL(from: text) {
            await send(.downloadQueue(.addURLs([url])))
          } else {
            await send(.showQuickAddPopup)
          }
        }

      case .onLaunch:
        return .merge(
          .run { send in
            for await _ in hotkeyClient.shortcutTriggered() {
              await send(.hotkeyPressed)
            }
          },
          .run { _ in await completionFeedbackClient.requestAuthorization() },
          .run { send in
            for await fileURL in completionFeedbackClient.notificationClicked() {
              await send(.fileRevealRequested(fileURL))
            }
          },
          // Needed for `clipboardClient.readString()`'s synthetic ⌘C (captures
          // whatever's selected in the frontmost app, even if never explicitly
          // copied) to actually be able to post that keystroke into another app.
          .run { _ in clipboardClient.requestAccessibilityAuthorizationIfNeeded() },
          .send(.settings(.onAppear)),
          .run { send in await send(.historyLoaded(historyClient.load())) }
        )

      case let .quickAdd(.presented(.delegate(.submitted(urls)))):
        state.quickAdd = nil
        return .send(.downloadQueue(.addURLs(urls)))

      case .quickAdd(.presented(.delegate(.cancelled))):
        state.quickAdd = nil
        return .none

      case .quickAdd:
        return .none

      case .settings(.delegate(.clearHistoryRequested)):
        state.history.records.removeAll()
        return .run { _ in try? historyClient.save([]) }

      case .settings:
        return .none

      case .showQuickAddPopup:
        guard state.quickAdd == nil else { return .none }
        state.quickAdd = QuickAddFeature.State()
        return .none

      case .statusBar:
        return .none
      }
    }
    .ifLet(\.$quickAdd, action: \.quickAdd) {
      QuickAddFeature()
    }
  }

  /// Records a settled (finished or failed) download to history, persists it,
  /// refreshes the tray icon, and fires completion feedback if enabled.
  private func handleDownloadSettled(
    _ state: inout State,
    id: UUID,
    savedFileURL: URL?,
    isFailure: Bool
  ) -> Effect<Action> {
    guard let item = state.downloadQueue.items[id: id] else {
      return refreshStatusBarEffect(state, justFinishedFileName: nil)
    }
    let fileName = savedFileURL?.lastPathComponent ?? item.sourceURL.lastPathComponent
    let record = DownloadRecord(
      sourceURL: item.sourceURL,
      fileName: fileName,
      savedFileURL: savedFileURL,
      completedAt: now,
      didFail: isFailure
    )
    state.history.records.insert(record, at: 0)
    let maxHistoryItems = state.settings.settings.maxHistoryItems
    if state.history.records.count > maxHistoryItems {
      state.history.records.removeLast(state.history.records.count - maxHistoryItems)
    }

    var effects: [Effect<Action>] = [
      .run { [records = state.history.records] _ in try? historyClient.save(records) },
      refreshStatusBarEffect(state, justFinishedFileName: isFailure ? nil : fileName),
    ]
    if !isFailure, state.settings.settings.notifyOnCompletion {
      effects.append(
        .run { _ in await completionFeedbackClient.notifyDownloadFinished(fileName, savedFileURL) }
      )
    }
    if !isFailure, state.settings.settings.playSoundOnCompletion {
      effects.append(.run { _ in completionFeedbackClient.playSound() })
    }
    return .merge(effects)
  }

  private func refreshStatusBarEffect(_ state: State, justFinishedFileName: String?) -> Effect<Action> {
    .send(
      .statusBar(
        .downloadQueueChanged(
          activeCount: state.downloadQueue.downloadingCount,
          overallFraction: state.downloadQueue.overallFractionCompleted,
          justFinishedFileName: justFinishedFileName
        )
      )
    )
  }
}
