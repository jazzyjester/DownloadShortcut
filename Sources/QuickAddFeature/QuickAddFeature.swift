import ComposableArchitecture
import Foundation

/// The small popup that appears near the cursor when the global shortcut fires:
/// pre-filled from the clipboard (by `AppFeature`, at the moment the shortcut fires —
/// see `HotkeyClient`), submits one or more URLs to be downloaded.
@Reducer
public struct QuickAddFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var urlText: String
    public var validationError: String?
    /// When the current `urlText` was seeded from the clipboard, so the view can show
    /// the user how fresh (or stale) the pasted item is.
    public var pastedAt: Date?

    public init(urlText: String = "", pastedAt: Date? = nil) {
      self.urlText = urlText
      self.pastedAt = pastedAt
    }

    /// Live validity, recomputed from `urlText` as it changes — lets the view show
    /// "this is a valid URL" (or not) without waiting for a submit attempt.
    public var isValid: Bool {
      !QuickAddFeature.parseURLs(from: urlText).isEmpty
    }
  }

  public enum Action: BindableAction, Sendable {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case delegate(Delegate)
    case submitButtonTapped

    @CasePathable
    public enum Delegate: Sendable {
      case cancelled
      case submitted(urls: [URL])
    }
  }

  public init() {}

  public var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.validationError = nil
        return .none

      case .cancelButtonTapped:
        return .send(.delegate(.cancelled))

      case .delegate:
        return .none

      case .submitButtonTapped:
        let urls = Self.parseURLs(from: state.urlText)
        guard !urls.isEmpty else {
          state.validationError = "Enter at least one valid URL."
          return .none
        }
        return .send(.delegate(.submitted(urls: urls)))
      }
    }
  }

  /// Splits on newlines so pasting/typing several URLs at once queues them all,
  /// keeping only lines that parse as an absolute URL with a scheme and host.
  public static func parseURLs(from text: String) -> [URL] {
    text
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .compactMap { line in
        guard let url = URL(string: line), url.scheme != nil, url.host != nil else { return nil }
        return url
      }
  }

  /// Finds the first URL anywhere inside arbitrary text — not just text that's
  /// *entirely* a URL — and normalizes it into something downloadable. Handles a
  /// normal `http(s)://…` URL embedded anywhere (e.g. in a sentence or a JSON blob),
  /// a protocol-relative `//host/path` URL, and a bare `host/path` with no scheme at
  /// all (both common in JSON API responses/network-inspector copies). `NSDataDetector`
  /// recognizes all three, but defaults to `http://` for the latter two; this prefers
  /// `https://` whenever the original text didn't already spell out a scheme.
  public static func extractURL(from text: String) -> URL? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }

    let range = NSRange(text.startIndex..., in: text)
    for match in detector.matches(in: text, range: range) {
      guard let url = match.url, url.host != nil, let matchRange = Range(match.range, in: text)
      else { continue }

      let matchedText = text[matchRange]
      if matchedText.hasPrefix("http://") || matchedText.hasPrefix("https://") {
        return url
      }
      // No explicit scheme in the source text (e.g. "//host/path" or "host/path") —
      // the detector inferred one; prefer https over its http default.
      let hostAndPath = matchedText.drop(while: { $0 == "/" })
      if let httpsURL = URL(string: "https://" + hostAndPath), httpsURL.host != nil {
        return httpsURL
      }
      return url
    }

    return nil
  }
}
