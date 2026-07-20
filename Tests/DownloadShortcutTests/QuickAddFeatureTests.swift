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

  @Test func onAppearFixesUpAClipboardURLWithNoScheme() async {
    // e.g. "example.com/file.zip" copied without "https://" — recognized and fixed
    // up to a real URL, rather than the box staying blank or unusable as-is.
    let store = TestStore(initialState: QuickAddFeature.State()) {
      QuickAddFeature()
    } withDependencies: {
      $0.clipboardClient.readString = { "example.com/file.zip" }
    }

    await store.send(.onAppear)
    await store.receive(\.clipboardRead) {
      $0.urlText = "https://example.com/file.zip"
    }
    #expect(store.state.isValid)
  }

  @Test func onAppearExtractsAndFixesAProtocolRelativeURLBuriedInJSON() async {
    // Matches a real "copy from a network inspector" scenario: a JSON fragment with
    // a protocol-relative URL (no scheme) inside a quoted field.
    let json = """
      "src": "//cdn.example.com/media/archive/low/some-video-id/archive_low.mp4",
      """
    let store = TestStore(initialState: QuickAddFeature.State()) {
      QuickAddFeature()
    } withDependencies: {
      $0.clipboardClient.readString = { json }
    }

    await store.send(.onAppear)
    await store.receive(\.clipboardRead) {
      $0.urlText = "https://cdn.example.com/media/archive/low/some-video-id/archive_low.mp4"
    }
    #expect(store.state.isValid)
  }

  @Test func onAppearExtractsAURLEmbeddedInASentence() async {
    let store = TestStore(initialState: QuickAddFeature.State()) {
      QuickAddFeature()
    } withDependencies: {
      $0.clipboardClient.readString = { "check this out: https://example.com/file.zip it's great" }
    }

    await store.send(.onAppear)
    await store.receive(\.clipboardRead) {
      $0.urlText = "https://example.com/file.zip"
    }
  }

  @Test func onAppearLeavesTextBlankWhenClipboardIsEmpty() async {
    let store = TestStore(initialState: QuickAddFeature.State()) {
      QuickAddFeature()
    } withDependencies: {
      $0.clipboardClient.readString = { nil }
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
