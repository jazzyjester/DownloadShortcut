import AppFeature
import AppKit
import ComposableArchitecture
import SettingsFeature
import SwiftUI

/// A directly-managed settings window. `LSUIElement` (accessory) apps have no
/// application menu bar, so there's no reliable responder chain to catch AppKit's
/// legacy `showSettingsWindow:` selector-based approach to opening SwiftUI's
/// `Settings` scene — clicking "Settings…" in the status item's menu would silently
/// no-op. Owning the window directly, the same way `QuickAddPanel` owns its panel,
/// sidesteps that entirely.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  private let store: StoreOf<AppFeature>
  private var window: NSWindow?

  init(store: StoreOf<AppFeature>) {
    self.store = store
  }

  func show() {
    if let window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let settingsStore = store.scope(state: \.settings, action: \.settings)
    let hostingView = NSHostingView(rootView: SettingsView(store: settingsStore))

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "DownloadShortcut Settings"
    window.contentView = hostingView
    window.isReleasedWhenClosed = false
    window.center()
    window.delegate = self

    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
  }
}
