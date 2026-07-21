import ComposableArchitecture
import Foundation
import Testing

@testable import QuickAddFeature

@MainActor
struct QuickAddFeatureTests {
  @Test func extractURLRecognizesAPlainHTTPSURL() {
    #expect(
      QuickAddFeature.extractURL(from: "https://example.com/file.zip")
        == URL(string: "https://example.com/file.zip")
    )
  }

  @Test func extractURLFixesUpATextWithNoScheme() {
    // e.g. "example.com/file.zip" copied without "https://" — recognized and fixed
    // up to a real URL, rather than being unusable as-is.
    #expect(
      QuickAddFeature.extractURL(from: "example.com/file.zip")
        == URL(string: "https://example.com/file.zip")
    )
  }

  @Test func extractURLFixesUpAProtocolRelativeURLBuriedInJSON() {
    // Matches a real "copy from a network inspector" scenario: a JSON fragment with
    // a protocol-relative URL (no scheme) inside a quoted field.
    let json = """
      "src": "//cdn.example.com/media/archive/low/some-video-id/archive_low.mp4",
      """
    #expect(
      QuickAddFeature.extractURL(from: json)
        == URL(string: "https://cdn.example.com/media/archive/low/some-video-id/archive_low.mp4")
    )
  }

  @Test func extractURLFindsAURLEmbeddedInASentence() {
    #expect(
      QuickAddFeature.extractURL(from: "check this out: https://example.com/file.zip it's great")
        == URL(string: "https://example.com/file.zip")
    )
  }

  @Test func extractURLReturnsNilForTextWithNoURL() {
    #expect(QuickAddFeature.extractURL(from: "not a url") == nil)
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
