import AppFeature
import AppKit
import ComposableArchitecture
import DownloadQueueFeature
import HistoryFeature
// See HotkeyClient.swift for why this needs `@preconcurrency`.
import HotkeyClient
@preconcurrency import KeyboardShortcuts
import SharedModels
import StatusBarFeature
import SwiftUI

/// Owns the `NSStatusItem`: renders the current `StatusBarFeature.State.Phase` as a
/// SwiftUI icon, and builds the history/settings/quit menu fresh each time it opens.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
  private let store: StoreOf<AppFeature>
  private let onSettingsRequested: () -> Void
  private let statusItem: NSStatusItem
  private let iconHostingView: NSHostingView<StatusBarIconView>

  init(store: StoreOf<AppFeature>, onSettingsRequested: @escaping () -> Void) {
    self.store = store
    self.onSettingsRequested = onSettingsRequested
    // `.variableLength`: the item's width tracks the hosted SwiftUI content's actual
    // size (see `resizeToFitContent`) instead of a fixed width that leaves a lot of
    // blank space around the small idle icon.
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.iconHostingView = NSHostingView(rootView: StatusBarIconView(phase: store.statusBar.phase))

    super.init()

    if let button = statusItem.button {
      button.addSubview(iconHostingView)
    }
    resizeToFitContent()

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
      Task { @MainActor in
        self?.resizeToFitContent()
        self?.observeIcon()
      }
    }
  }

  /// Sizes the status item (and its hosted view) to whatever the current icon
  /// content actually needs — a small square when idle, wider while the "100% (3)"
  /// progress text is showing.
  private func resizeToFitContent() {
    let fittingSize = iconHostingView.fittingSize
    let width = max(fittingSize.width, 22)
    statusItem.length = width
    if let button = statusItem.button {
      iconHostingView.frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
    }
  }

  func menuWillOpen(_ menu: NSMenu) {
    menu.removeAllItems()

    let shortcutDescription = KeyboardShortcuts.getShortcut(for: .quickDownload)?.description ?? "Not set"
    let shortcutItem = NSMenuItem(title: "Shortcut: \(shortcutDescription)", action: nil, keyEquivalent: "")
    shortcutItem.isEnabled = false
    menu.addItem(shortcutItem)
    menu.addItem(.separator())

    addCancelItems(to: menu)

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
      ActionMenuItem(title: "Settings…") { [weak self] in
        self?.onSettingsRequested()
      }
    )
    menu.addItem(
      ActionMenuItem(title: "Quit DownloadShortcut") {
        NSApp.terminate(nil)
      }
    )
  }

  /// Active (downloading or still-queued) items can be cancelled. With exactly one,
  /// a single "Cancel Download" item cancels it directly; with more than one, a
  /// submenu lists each by name so the user picks which one — rather than an
  /// ambiguous single action guessing for them.
  private func addCancelItems(to menu: NSMenu) {
    let activeItems = store.downloadQueue.items.filter { $0.status.countsTowardConcurrencyLimit }
    guard !activeItems.isEmpty else { return }

    if activeItems.count == 1, let item = activeItems.first {
      menu.addItem(
        ActionMenuItem(title: "Cancel “\(item.sourceURL.lastPathComponent)”") { [weak self] in
          self?.cancelDownload(id: item.id)
        }
      )
    } else {
      let cancelItem = NSMenuItem(title: "Cancel Download…", action: nil, keyEquivalent: "")
      let submenu = NSMenu()
      for item in activeItems {
        submenu.addItem(
          ActionMenuItem(title: item.sourceURL.lastPathComponent) { [weak self] in
            self?.cancelDownload(id: item.id)
          }
        )
      }
      submenu.addItem(.separator())
      submenu.addItem(
        ActionMenuItem(title: "Cancel All") { [weak self] in
          for item in activeItems {
            self?.cancelDownload(id: item.id)
          }
        }
      )
      cancelItem.submenu = submenu
      menu.addItem(cancelItem)
    }
    menu.addItem(.separator())
  }

  private func cancelDownload(id: DownloadItem.State.ID) {
    store.send(.downloadQueue(.items(.element(id: id, action: .cancelButtonTapped))))
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
