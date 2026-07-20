import ComposableArchitecture
import Testing

@testable import SettingsFeature
@testable import SharedModels

@MainActor
struct SettingsFeatureTests {
  @Test func onAppearLoadsPersistedSettings() async {
    let persisted = AppSettings(maxConcurrentDownloads: 5, notifyOnCompletion: false)
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.settingsClient.load = { persisted }
      $0.launchAtLoginClient.isEnabled = { true }
    }

    await store.send(.onAppear)
    await store.receive(\.settingsLoaded) {
      $0.settings = persisted
      $0.isLaunchAtLoginEnabled = true
    }
  }

  @Test func changingMaxConcurrentDownloadsPersists() async {
    let savedSettings = LockIsolated<AppSettings?>(nil)
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.settingsClient.save = { savedSettings.setValue($0) }
    }

    await store.send(.maxConcurrentDownloadsChanged(5)) {
      $0.settings.maxConcurrentDownloads = 5
    }
    await store.finish()
    #expect(savedSettings.value?.maxConcurrentDownloads == 5)
  }

  @Test func launchAtLoginFailureRevertsTheToggleAndSurfacesAnError() async {
    struct RegistrationError: Error {}
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.launchAtLoginClient.setEnabled = { _ in throw RegistrationError() }
      $0.launchAtLoginClient.isEnabled = { false }
    }

    await store.send(.launchAtLoginToggleChanged(true)) {
      $0.isLaunchAtLoginEnabled = true
    }
    await store.receive(\.launchAtLoginUpdateFailed) {
      $0.isLaunchAtLoginEnabled = false
      $0.launchAtLoginError = RegistrationError().localizedDescription
    }
  }

  @Test func clearHistoryButtonSendsDelegate() async {
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    }

    await store.send(.clearHistoryButtonTapped)
    await store.receive(\.delegate.clearHistoryRequested)
  }
}
