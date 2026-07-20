import ComposableArchitecture
import Testing

@testable import StatusBarFeature

@MainActor
struct StatusBarFeatureTests {
  @Test func goesIdleWhenNothingIsActive() async {
    let store = TestStore(initialState: StatusBarFeature.State()) {
      StatusBarFeature()
    }

    await store.send(.downloadQueueChanged(activeCount: 0, overallFraction: nil, justFinishedFileName: nil))
  }

  @Test func showsProgressWhileDownloading() async {
    let store = TestStore(initialState: StatusBarFeature.State()) {
      StatusBarFeature()
    }

    await store.send(
      .downloadQueueChanged(activeCount: 1, overallFraction: 0.5, justFinishedFileName: nil)
    ) {
      $0.phase = .downloading(activeCount: 1, overallFraction: 0.5)
    }
  }

  @Test func justFinishedRevertsToIdleAfterTheFlourish() async {
    let clock = TestClock()
    let store = TestStore(initialState: StatusBarFeature.State()) {
      StatusBarFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(
      .downloadQueueChanged(activeCount: 0, overallFraction: nil, justFinishedFileName: "movie.mp4")
    ) {
      $0.phase = .justFinished(fileName: "movie.mp4")
    }

    await clock.advance(by: .seconds(2))
    await store.receive(\.justFinishedFlourishElapsed) {
      $0.phase = .idle
    }
  }
}
