import ComposableArchitecture
import Foundation
import Testing

@testable import DownloadClient
@testable import DownloadQueueFeature

@MainActor
struct DownloadQueueFeatureTests {
  private let url1 = URL(string: "https://example.com/a.zip")!
  private let url2 = URL(string: "https://example.com/b.zip")!

  @Test func onlyMaxConcurrentItemsStartImmediately() async {
    // A stream that stays open until we explicitly finish it below, standing in for
    // a download that's still in flight.
    let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()
    let store = TestStore(
      initialState: DownloadQueueFeature.State(maxConcurrentDownloads: 1)
    ) {
      DownloadQueueFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.downloadClient.events = { _ in stream }
    }

    let id1 = UUID(0)
    let id2 = UUID(1)

    await store.send(.addURLs([url1, url2])) {
      $0.items = [
        DownloadItem.State(id: id1, sourceURL: self.url1),
        DownloadItem.State(id: id2, sourceURL: self.url2),
      ]
    }
    await store.receive(\.items[id: id1].start) {
      $0.items[id: id1]?.status = .downloading(fractionCompleted: 0)
    }
    // The second item stays queued: only one concurrent slot was allowed.
    #expect(store.state.items[id: id2]?.status == .queued)

    continuation.finish()
    await store.finish()
  }

  @Test func aFreedSlotStartsTheNextQueuedItem() async {
    let store = TestStore(
      initialState: DownloadQueueFeature.State(maxConcurrentDownloads: 1)
    ) {
      DownloadQueueFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.downloadClient.events = { url in
        AsyncStream { continuation in
          continuation.yield(.progress(fractionCompleted: 1))
          continuation.yield(
            .finished(
              temporaryFileURL: URL(fileURLWithPath: "/tmp/staged"),
              suggestedFileName: url.lastPathComponent,
              byteCount: 10
            )
          )
          continuation.finish()
        }
      }
      $0.downloadClient.moveToDownloads = { _, suggestedFileName in
        URL(fileURLWithPath: "/tmp/Downloads/\(suggestedFileName)")
      }
    }

    let id1 = UUID(0)
    let id2 = UUID(1)
    let savedURL1 = URL(fileURLWithPath: "/tmp/Downloads/a.zip")
    let savedURL2 = URL(fileURLWithPath: "/tmp/Downloads/b.zip")

    await store.send(.addURLs([url1, url2])) {
      $0.items = [
        DownloadItem.State(id: id1, sourceURL: self.url1),
        DownloadItem.State(id: id2, sourceURL: self.url2),
      ]
    }
    await store.receive(\.items[id: id1].start) {
      $0.items[id: id1]?.status = .downloading(fractionCompleted: 0)
    }
    await store.receive(\.items[id: id1].downloadEvent) {
      $0.items[id: id1]?.status = .downloading(fractionCompleted: 1)
    }
    await store.receive(\.items[id: id1].downloadEvent)
    await store.receive(\.items[id: id1].moveResponse) {
      $0.items[id: id1]?.status = .finished(fileURL: savedURL1)
    }
    // The first item finishing frees a slot, so the second starts automatically.
    await store.receive(\.items[id: id2].start) {
      $0.items[id: id2]?.status = .downloading(fractionCompleted: 0)
    }
    await store.receive(\.items[id: id2].downloadEvent) {
      $0.items[id: id2]?.status = .downloading(fractionCompleted: 1)
    }
    await store.receive(\.items[id: id2].downloadEvent)
    await store.receive(\.items[id: id2].moveResponse) {
      $0.items[id: id2]?.status = .finished(fileURL: savedURL2)
    }
  }

  @Test func cancellingAnItemFreesItsSlot() async {
    let (stream1, continuation1) = AsyncStream<DownloadEvent>.makeStream()
    let (stream2, continuation2) = AsyncStream<DownloadEvent>.makeStream()
    let store = TestStore(
      initialState: DownloadQueueFeature.State(maxConcurrentDownloads: 1)
    ) {
      DownloadQueueFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.downloadClient.events = { [url1] url in url == url1 ? stream1 : stream2 }
    }

    let id1 = UUID(0)
    let id2 = UUID(1)

    await store.send(.addURLs([url1, url2])) {
      $0.items = [
        DownloadItem.State(id: id1, sourceURL: self.url1),
        DownloadItem.State(id: id2, sourceURL: self.url2),
      ]
    }
    await store.receive(\.items[id: id1].start) {
      $0.items[id: id1]?.status = .downloading(fractionCompleted: 0)
    }

    await store.send(.items(.element(id: id1, action: .cancelButtonTapped))) {
      $0.items[id: id1]?.status = .cancelled
    }
    // Cancelling the first download frees its slot for the queued second one.
    await store.receive(\.items[id: id2].start) {
      $0.items[id: id2]?.status = .downloading(fractionCompleted: 0)
    }

    continuation1.finish()
    continuation2.finish()
    await store.finish()
  }
}
