import ComposableArchitecture
import Testing

@testable import ClipboardClient
@testable import QuickAddFeature

@MainActor
struct QuickAddFeatureTests {
  @Test func onAppearSeedsFromAURLShapedClipboard() async {
    let store = TestStore(initialState: QuickAddFeature.State()) {
      QuickAddFeature()
    } withDependencies: {
      $0.clipboardClient.readString = { "https://example.com/file.zip" }
    }

    await store.send(.onAppear)
    await store.receive(\.clipboardRead) {
      $0.urlText = "https://example.com/file.zip"
    }
  }

  @Test func onAppearIgnoresNonURLClipboardContent() async {
    let store = TestStore(initialState: QuickAddFeature.State()) {
      QuickAddFeature()
    } withDependencies: {
      $0.clipboardClient.readString = { "just some copied sentence" }
    }

    await store.send(.onAppear)
    await store.receive(\.clipboardRead)
  }

  @Test func submitWithBlankTextShowsValidationError() async {
    let store = TestStore(initialState: QuickAddFeature.State()) {
      QuickAddFeature()
    }

    await store.send(.submitButtonTapped) {
      $0.validationError = "Enter at least one valid URL."
    }
  }

  @Test func submitWithMultipleLinesParsesEachURL() async {
    let store = TestStore(
      initialState: QuickAddFeature.State(
        urlText: "https://example.com/a.zip\nhttps://example.com/b.zip"
      )
    ) {
      QuickAddFeature()
    }

    await store.send(.submitButtonTapped)
    await store.receive(\.delegate.submitted)
  }

  @Test func cancelSendsDelegate() async {
    let store = TestStore(initialState: QuickAddFeature.State()) {
      QuickAddFeature()
    }

    await store.send(.cancelButtonTapped)
    await store.receive(\.delegate.cancelled)
  }
}
