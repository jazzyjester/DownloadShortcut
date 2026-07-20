import AppFeature
import AppKit
import ComposableArchitecture
import HistoryFeature
import SharedModels
import StatusBarFeature
import SwiftUI

/// Owns the `NSStatusItem`: renders the current `StatusBarFeature.State.Phase` as a
/// SwiftUI icon, and builds the history/settings/quit menu fresh each time it opens.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
  private let store: StoreOf<AppFeature>
  private let statusItem: NSStatusItem
  private let iconHostingView: NSHostingView<StatusBarIconView>

  init(store: StoreOf<AppFeature>) {
    self.store = store
    self.statusItem = NSStatusBar.system.statusItem(withLength: 60)
    self.iconHostingView = NSHostingView(rootView: StatusBarIconView(phase: store.statusBar.phase))

    super.init()

    if let button = statusItem.button {
      iconHostingView.frame = button.bounds
      iconHostingView.autoresizingMask = [.width, .height]
      button.addSubview(iconHostingView)
    }

    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    observeIcon()
  }

  /// Re-renders the SwiftUI icon whenever `store.statusBar.phase` changes, using the
  /// standard Observation "read, then re-subscribe on change" pattern for driving
  /// AppKit from `@ObservableState` outside of a SwiftUI view hierarchy.
  private func observeIcon() {
    withObservationTracking {
      iconHostingView.rootView = StatusBarIconView(phase: store.statusBar.phase)
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeIcon() }
    }
  }

  func menuWillOpen(_ menu: NSMenu) {
    menu.removeAllItems()

    let records = store.history.records
    if records.isEmpty {
      let emptyItem = NSMenuItem(title: "No downloads yet", action: nil, keyEquivalent: "")
      emptyItem.isEnabled = false
      menu.addItem(emptyItem)
    } else {
      for record in records {
        let item = NSMenuItem(title: record.fileName, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(
          ActionMenuItem(title: "Open") { [weak self] in
            self?.store.send(.history(.openButtonTapped(id: record.id)))
          }
        )
        submenu.addItem(
          ActionMenuItem(title: "Show in Finder") { [weak self] in
            self?.store.send(.history(.revealInFinderButtonTapped(id: record.id)))
          }
        )
        item.submenu = submenu
        menu.addItem(item)
      }

      menu.addItem(.separator())
      menu.addItem(
        ActionMenuItem(title: "Clear History") { [weak self] in
          self?.store.send(.history(.clearHistoryButtonTapped))
        }
      )
    }

    menu.addItem(.separator())
    menu.addItem(
      ActionMenuItem(title: "Settings…") {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
      }
    )
    menu.addItem(
      ActionMenuItem(title: "Quit DownloadShortcut") {
        NSApp.terminate(nil)
      }
    )
  }
}

/// An `NSMenuItem` that runs a closure directly, instead of requiring a separate
/// target/action pair for every menu action.
private final class ActionMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(title: String, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(invoke), keyEquivalent: "")
    self.target = self
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func invoke() {
    handler()
  }
}
