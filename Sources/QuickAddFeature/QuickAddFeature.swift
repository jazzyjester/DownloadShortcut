import ClipboardClient
import ComposableArchitecture
import Foundation

/// The small popup that appears near the cursor when the global shortcut fires:
/// pre-filled from the clipboard, submits one or more URLs to be downloaded.
@Reducer
public struct QuickAddFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var urlText: String
    public var validationError: String?

    public init(urlText: String = "") {
      self.urlText = urlText
    }
  }

  public enum Action: BindableAction, Sendable {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case clipboardRead(String?)
    case delegate(Delegate)
    case onAppear
    case submitButtonTapped

    @CasePathable
    public enum Delegate: Sendable {
      case cancelled
      case submitted(urls: [URL])
    }
  }

  public init() {}

  @Dependency(\.clipboardClient) var clipboardClient

  public var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.validationError = nil
        return .none

      case .cancelButtonTapped:
        return .send(.delegate(.cancelled))

      case let .clipboardRead(text):
        // Always seed from the clipboard, even if it isn't a full "https://..." URL
        // yet (e.g. "example.com/file.zip" copied without a scheme) — validation
        // happens on submit, so the user can see and fix it up here instead of the
        // box silently staying blank.
        state.urlText = text ?? ""
        return .none

      case .delegate:
        return .none

      case .onAppear:
        return .run { send in
          await send(.clipboardRead(clipboardClient.readString()))
        }

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
  static func parseURLs(from text: String) -> [URL] {
    text
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .compactMap { line in
        guard let url = URL(string: line), url.scheme != nil, url.host != nil else { return nil }
        return url
      }
  }
}
