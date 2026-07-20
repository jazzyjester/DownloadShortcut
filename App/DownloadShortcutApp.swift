import ComposableArchitecture
import SettingsFeature
import SwiftUI

@main
struct DownloadShortcutApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // The standard macOS Settings window (⌘,), backed by the same store the status
    // item and popup use. There's no other window, so this is the app's only Scene.
    Settings {
      SettingsView(store: appDelegate.store.scope(state: \.settings, action: \.settings))
    }
  }
}
