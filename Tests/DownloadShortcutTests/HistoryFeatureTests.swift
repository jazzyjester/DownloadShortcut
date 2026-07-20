import ComposableArchitecture
import Foundation
import Testing

@testable import FileActionsClient
@testable import HistoryFeature
@testable import SharedModels

@MainActor
struct HistoryFeatureTests {
  private func makeRecord(fileURL: URL) -> DownloadRecord {
    DownloadRecord(
      sourceURL: URL(string: "https://example.com/file.zip")!,
      fileName: fileURL.lastPathComponent,
      savedFileURL: fileURL,
      completedAt: Date(timeIntervalSince1970: 0)
    )
  }

  @Test func openButtonOpensTheSavedFile() async {
    let fileURL = URL(fileURLWithPath: "/tmp/Downloads/file.zip")
    let record = makeRecord(fileURL: fileURL)
    let openedFileURL = LockIsolated<URL?>(nil)

    let store = TestStore(initialState: HistoryFeature.State(records: [record])) {
      HistoryFeature()
    } withDependencies: {
      $0.fileActionsClient.openFile = { openedFileURL.setValue($0) }
    }

    await store.send(.openButtonTapped(id: record.id))
    #expect(openedFileURL.value == fileURL)
  }

  @Test func revealButtonRevealsInFinder() async {
    let fileURL = URL(fileURLWithPath: "/tmp/Downloads/file.zip")
    let record = makeRecord(fileURL: fileURL)
    let revealedFileURL = LockIsolated<URL?>(nil)

    let store = TestStore(initialState: HistoryFeature.State(records: [record])) {
      HistoryFeature()
    } withDependencies: {
      $0.fileActionsClient.revealInFinder = { revealedFileURL.setValue($0) }
    }

    await store.send(.revealInFinderButtonTapped(id: record.id))
    #expect(revealedFileURL.value == fileURL)
  }

  @Test func clearHistoryEmptiesTheList() async {
    let record = makeRecord(fileURL: URL(fileURLWithPath: "/tmp/Downloads/file.zip"))
    let store = TestStore(initialState: HistoryFeature.State(records: [record])) {
      HistoryFeature()
    }

    await store.send(.clearHistoryButtonTapped) {
      $0.records = []
    }
  }
}
