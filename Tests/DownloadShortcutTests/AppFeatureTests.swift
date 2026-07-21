import ComposableArchitecture
import Foundation
import Testing

@testable import AppFeature
@testable import DownloadQueueFeature
@testable import FileActionsClient
@testable import QuickAddFeature
@testable import SettingsFeature
@testable import SharedModels
@testable import StatusBarFeature

@MainActor
struct AppFeatureTests {
  @Test func hotkeyPressedPresentsTheQuickAddPopupEmptyWhenNothingWasCaptured() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.hotkeyPressed(seedText: nil)) {
      $0.quickAdd = QuickAddFeature.State()
    }
  }

  @Test func hotkeyPressedSeedsThePopupFromCapturedTextAndFixesUpTheURL() async {
    // The text has already been captured (including any synthetic-copy attempt) by
    // the time this action fires — see HotkeyClient — so this just has to seed the
    // popup with it, same URL-extraction/fixup as before.
    let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    let json = """
      "src": "//cdn.example.com/media/archive/low/some-video-id/archive_low.mp4",
      """
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.date.now = fixedNow
    }

    await store.send(.hotkeyPressed(seedText: json)) {
      $0.quickAdd = QuickAddFeature.State(
        urlText: "https://cdn.example.com/media/archive/low/some-video-id/archive_low.mp4",
        pastedAt: fixedNow
      )
    }
  }

  @Test func hotkeyPressedWhilePopupIsAlreadyShowingIsANoOp() async {
    let store = TestStore(
      initialState: AppFeature.State(quickAdd: QuickAddFeature.State(urlText: "https://example.com"))
    ) {
      AppFeature()
    }

    await store.send(.hotkeyPressed(seedText: "https://example.com/other.zip"))
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

  @Test func hotkeyPressedSkipsThePopupAndDownloadsWhenAutoDownloadIsOnAndCapturedTextHasAValidURL() async {
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
      $0.uuid = .incrementing
    }
    store.exhaustivity = .off

    await store.send(.hotkeyPressed(seedText: "https://example.com/file.zip"))
    await store.finish()
    await store.skipReceivedActions()

    #expect(store.state.quickAdd == nil)
    #expect(store.state.downloadQueue.items.count == 1)
    #expect(store.state.downloadQueue.items.first?.sourceURL == URL(string: "https://example.com/file.zip"))
  }

  @Test func hotkeyPressedFallsBackToThePopupWhenAutoDownloadIsOnButCapturedTextHasNoValidURL() async {
    var settings = AppSettings.default
    settings.autoDownloadWhenClipboardHasValidURL = true
    let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    let store = TestStore(
      initialState: AppFeature.State(settings: SettingsFeature.State(settings: settings))
    ) {
      AppFeature()
    } withDependencies: {
      $0.date.now = fixedNow
    }

    await store.send(.hotkeyPressed(seedText: "not a url")) {
      $0.quickAdd = QuickAddFeature.State(urlText: "not a url", pastedAt: fixedNow)
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
