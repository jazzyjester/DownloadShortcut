import ComposableArchitecture
import Foundation
import Testing

@testable import AppFeature
@testable import DownloadQueueFeature
@testable import QuickAddFeature
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
      $0.completionFeedbackClient.notifyDownloadFinished = { _ in }
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
}
