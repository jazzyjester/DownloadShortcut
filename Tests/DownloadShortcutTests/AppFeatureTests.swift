import ComposableArchitecture
import Foundation
import Testing

@testable import AppFeature
@testable import ClipboardClient
@testable import DownloadQueueFeature
@testable import FileActionsClient
@testable import QuickAddFeature
@testable import SettingsFeature
@testable import SharedModels
@testable import StatusBarFeature

@MainActor
struct AppFeatureTests {
  @Test func hotkeyPressedPresentsTheQuickAddPopup() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.hotkeyPressed) {
      $0.quickAdd = QuickAddFeature.State()
    }
  }

  @Test func hotkeyPressedWhilePopupIsAlreadyShowingIsANoOp() async {
    let store = TestStore(
      initialState: AppFeature.State(quickAdd: QuickAddFeature.State(urlText: "https://example.com"))
    ) {
      AppFeature()
    }

    await store.send(.hotkeyPressed)
  }

  @Test func submittingAURLDownloadsItAndRecordsHistory() async {
    let url = URL(string: "https://example.com/report.pdf")!
    let store = TestStore(
      initialState: AppFeature.State(
        downloadQueue: DownloadQueueFeature.State(maxConcurrentDownloads: 1),
        quickAdd: QuickAddFeature.State(urlText: url.absoluteString)
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_000)
      $0.continuousClock = ImmediateClock()
      $0.downloadClient.events = { url in
        AsyncStream { continuation in
          continuation.yield(.progress(fractionCompleted: 1))
          continuation.yield(
            .finished(
              temporaryFileURL: URL(fileURLWithPath: "/tmp/staged"),
              suggestedFileName: url.lastPathComponent,
              byteCount: 42
            )
          )
          continuation.finish()
        }
      }
      $0.downloadClient.moveToDownloads = { _, suggestedFileName in
        URL(fileURLWithPath: "/tmp/Downloads/\(suggestedFileName)")
      }
      $0.historyClient.save = { _ in }
      $0.completionFeedbackClient.notifyDownloadFinished = { _, _ in }
    }
    store.exhaustivity = .off

    await store.send(.quickAdd(.presented(.submitButtonTapped)))
    await store.finish()
    // In non-exhaustive mode, `finish()` only drains in-flight effects (Tasks); it
    // doesn't apply already-queued *received* actions to the state `store.state`
    // exposes. `skipReceivedActions()` does that, without asserting on each one.
    await store.skipReceivedActions()

    #expect(store.state.quickAdd == nil)
    #expect(store.state.history.records.count == 1)
    #expect(store.state.history.records.first?.fileName == "report.pdf")
    #expect(store.state.history.records.first?.didFail == false)
    #expect(store.state.statusBar.phase == .idle)
  }

  @Test func hotkeyPressedSkipsThePopupAndDownloadsWhenAutoDownloadIsOnAndClipboardHasAValidURL() async {
    var settings = AppSettings.default
    settings.autoDownloadWhenClipboardHasValidURL = true
    let store = TestStore(
      initialState: AppFeature.State(
        downloadQueue: DownloadQueueFeature.State(maxConcurrentDownloads: 0),
        settings: SettingsFeature.State(settings: settings)
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.clipboardClient.readString = { "https://example.com/file.zip" }
      $0.uuid = .incrementing
    }
    store.exhaustivity = .off

    await store.send(.hotkeyPressed)
    await store.finish()
    await store.skipReceivedActions()

    #expect(store.state.quickAdd == nil)
    #expect(store.state.downloadQueue.items.count == 1)
    #expect(store.state.downloadQueue.items.first?.sourceURL == URL(string: "https://example.com/file.zip"))
  }

  @Test func hotkeyPressedFallsBackToThePopupWhenAutoDownloadIsOnButClipboardHasNoValidURL() async {
    var settings = AppSettings.default
    settings.autoDownloadWhenClipboardHasValidURL = true
    let store = TestStore(
      initialState: AppFeature.State(settings: SettingsFeature.State(settings: settings))
    ) {
      AppFeature()
    } withDependencies: {
      $0.clipboardClient.readString = { "not a url" }
    }

    await store.send(.hotkeyPressed)
    await store.receive(\.showQuickAddPopup) {
      $0.quickAdd = QuickAddFeature.State()
    }
  }

  @Test func fileRevealRequestedRevealsTheFileInFinder() async {
    let revealedFileURL = LockIsolated<URL?>(nil)
    let fileURL = URL(fileURLWithPath: "/tmp/Downloads/report.pdf")
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.fileActionsClient.revealInFinder = { revealedFileURL.setValue($0) }
    }

    await store.send(.fileRevealRequested(fileURL))
    await store.finish()

    #expect(revealedFileURL.value == fileURL)
  }
}
