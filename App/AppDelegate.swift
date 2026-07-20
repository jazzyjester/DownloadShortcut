import AppFeature
import AppKit
import ComposableArchitecture

/// Owns the app's single `Store` and the two pieces of AppKit UI that hang off of it:
/// the status item and the quick-add popup. No Dock icon, no main window — this is a
/// pure menu-bar utility (`LSUIElement` in Info.plist, reinforced at runtime below).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let store = Store(initialState: AppFeature.State()) {
    AppFeature()
  }

  private var statusBarController: StatusBarController?
  private var quickAddPanel: QuickAddPanel?
  private var settingsWindowController: SettingsWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let settingsWindowController = SettingsWindowController(store: store)
    self.settingsWindowController = settingsWindowController

    statusBarController = StatusBarController(store: store) {
      settingsWindowController.show()
    }
    quickAddPanel = QuickAddPanel(store: store)

    store.send(.onLaunch)
  }
}
