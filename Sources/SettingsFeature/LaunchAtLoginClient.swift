import ComposableArchitecture
import ServiceManagement

/// Wraps `SMAppService` so "Launch at login" is testable without touching the real
/// system login-item registry.
@DependencyClient
public struct LaunchAtLoginClient: Sendable {
  public var isEnabled: @Sendable () -> Bool = { false }
  public var setEnabled: @Sendable (_ enabled: Bool) throws -> Void
}

extension LaunchAtLoginClient: DependencyKey {
  public static let liveValue = LaunchAtLoginClient(
    isEnabled: { SMAppService.mainApp.status == .enabled },
    setEnabled: { enabled in
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    }
  )
}

extension DependencyValues {
  public var launchAtLoginClient: LaunchAtLoginClient {
    get { self[LaunchAtLoginClient.self] }
    set { self[LaunchAtLoginClient.self] = newValue }
  }
}
