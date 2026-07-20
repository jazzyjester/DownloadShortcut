import AppFeature
import AppKit
import ComposableArchitecture
import QuickAddFeature
import SwiftUI

/// The borderless popup that appears centered on screen when the global shortcut
/// fires. Presence is entirely driven by `AppFeature.State.quickAdd`: this class just
/// shows/hides an `NSPanel` to match, and turns "clicked away" into a cancel.
@MainActor
final class QuickAddPanel: NSObject, NSWindowDelegate {
  private let store: StoreOf<AppFeature>
  private var panel: NSPanel?

  init(store: StoreOf<AppFeature>) {
    self.store = store
    super.init()
    observePresentation()
  }

  private func observePresentation() {
    withObservationTracking {
      if store.quickAdd != nil {
        showIfNeeded()
      } else {
        dismiss()
      }
    } onChange: { [weak self] in
      Task { @MainActor in self?.observePresentation() }
    }
  }

  private func showIfNeeded() {
    guard panel == nil else { return }
    guard let childStore = store.scope(state: \.quickAdd, action: \.quickAdd.presented) else { return }

    let hostingView = NSHostingView(rootView: QuickAddView(store: childStore))
    let fittingSize = hostingView.fittingSize
    hostingView.frame = NSRect(origin: .zero, size: fittingSize)

    // Deliberately *not* `.nonactivatingPanel`: that flag tells AppKit "don't
    // activate the app when this becomes key", which directly fought the
    // `NSApp.activate` call below and left the popup shown-but-unfocused right
    // after the global hotkey fired — typing and Escape needed an extra click to
    // start working. We want this fully focused the instant it appears.
    let panel = KeyablePanel(
      contentRect: hostingView.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.contentView = hostingView
    panel.delegate = self

    centerOnScreen(panel)

    self.panel = panel
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    // Belt-and-suspenders for the global-hotkey path: activation can lag a beat
    // behind the calls above, so re-assert key status on the next run loop turn.
    DispatchQueue.main.async { [weak panel] in
      panel?.makeKeyAndOrderFront(nil)
    }
  }

  /// Centers the panel on whichever screen the mouse is currently over (falling back
  /// to the main screen), so it shows up on the display the user is actually using.
  private func centerOnScreen(_ panel: NSPanel) {
    let mouseLocation = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    else { return }

    let visibleFrame = screen.visibleFrame
    let origin = NSPoint(
      x: visibleFrame.midX - panel.frame.width / 2,
      y: visibleFrame.midY - panel.frame.height / 2
    )
    panel.setFrameOrigin(origin)
  }

  private func dismiss() {
    panel?.orderOut(nil)
    panel = nil
  }

  func windowDidResignKey(_ notification: Notification) {
    // Clicking away (or Escape, via QuickAddView's onExitCommand) dismisses without
    // starting a download.
    store.send(.quickAdd(.presented(.cancelButtonTapped)))
  }
}

/// `NSWindow.canBecomeKey` defaults to `false` for borderless windows — the panel
/// would show, but never actually become key, so its text field could never get
/// keyboard focus (this is why typing into the popup silently did nothing).
private final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool { true }
}
