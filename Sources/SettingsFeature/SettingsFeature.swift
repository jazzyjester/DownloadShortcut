import ComposableArchitecture
import Foundation
import SharedModels

@Reducer
public struct SettingsFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var settings: AppSettings = .default
    public var isLaunchAtLoginEnabled: Bool = false
    public var launchAtLoginError: String?

    public init(
      settings: AppSettings = .default,
      isLaunchAtLoginEnabled: Bool = false,
      launchAtLoginError: String? = nil
    ) {
      self.settings = settings
      self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
      self.launchAtLoginError = launchAtLoginError
    }
  }

  public enum Action: Sendable {
    case clearHistoryButtonTapped
    case delegate(Delegate)
    case launchAtLoginToggleChanged(Bool)
    case launchAtLoginUpdateFailed(message: String)
    case maxConcurrentDownloadsChanged(Int)
    case notifyOnCompletionToggleChanged(Bool)
    case onAppear
    case playSoundToggleChanged(Bool)
    case settingsLoaded(AppSettings, isLaunchAtLoginEnabled: Bool)

    @CasePathable
    public enum Delegate: Sendable {
      case clearHistoryRequested
    }
  }

  public init() {}

  @Dependency(\.settingsClient) var settingsClient
  @Dependency(\.launchAtLoginClient) var launchAtLoginClient

  public var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .clearHistoryButtonTapped:
        return .send(.delegate(.clearHistoryRequested))

      case .delegate:
        return .none

      case let .launchAtLoginToggleChanged(isEnabled):
        state.isLaunchAtLoginEnabled = isEnabled
        state.launchAtLoginError = nil
        return .run { send in
          do {
            try launchAtLoginClient.setEnabled(isEnabled)
          } catch {
            await send(.launchAtLoginUpdateFailed(message: error.localizedDescription))
          }
        }

      case let .launchAtLoginUpdateFailed(message):
        // Registration with the system can fail (e.g. outside a signed, installed
        // .app bundle); reflect that the toggle didn't actually take effect.
        state.isLaunchAtLoginEnabled = launchAtLoginClient.isEnabled()
        state.launchAtLoginError = message
        return .none

      case let .maxConcurrentDownloadsChanged(value):
        state.settings.maxConcurrentDownloads = max(1, value)
        return persist(state.settings)

      case let .notifyOnCompletionToggleChanged(isOn):
        state.settings.notifyOnCompletion = isOn
        return persist(state.settings)

      case .onAppear:
        return .run { send in
          await send(
            .settingsLoaded(settingsClient.load(), isLaunchAtLoginEnabled: launchAtLoginClient.isEnabled())
          )
        }

      case let .playSoundToggleChanged(isOn):
        state.settings.playSoundOnCompletion = isOn
        return persist(state.settings)

      case let .settingsLoaded(settings, isLaunchAtLoginEnabled):
        state.settings = settings
        state.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
        return .none
      }
    }
  }

  private func persist(_ settings: AppSettings) -> Effect<Action> {
    .run { _ in try? settingsClient.save(settings) }
  }
}
