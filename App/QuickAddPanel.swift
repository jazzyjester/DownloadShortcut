import AppFeature
import AppKit
import ComposableArchitecture
import QuickAddFeature
import SwiftUI

/// The popup that appears centered on screen when the global shortcut fires.
/// Presence is entirely driven by `AppFeature.State.quickAdd`: this class just
/// shows/hides an `NSWindow` to match, and turns "clicked away" into a cancel.
///
/// This is a *titled* window with its title bar hidden, rather than a `.borderless`
/// `NSPanel`. Borderless panels default `canBecomeKey` to `false` and, even after
/// overriding that, proved unreliable about actually taking key/focus status when
/// shown from a global hotkey (several async hops removed from the original
/// keypress) rather than a normal in-app click. Titled windows behave normally here
/// with no special-casing needed.
@MainActor
final class QuickAddPanel: NSObject, NSWindowDelegate {
  private let store: StoreOf<AppFeature>
  private var window: NSWindow?

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
    guard window == nil else { return }
    guard let childStore = store.scope(state: \.quickAdd, action: \.quickAdd.presented) else { return }

    let hostingView = NSHostingView(rootView: QuickAddView(store: childStore))
    let fittingSize = hostingView.fittingSize
    hostingView.frame = NSRect(origin: .zero, size: fittingSize)

    let window = NSWindow(
      contentRect: hostingView.frame,
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.isMovableByWindowBackground = true
    window.level = .floating
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.contentView = hostingView
    window.delegate = self

    centerOnScreen(window)

    self.window = window
    activateAndFocus(window, hostingView: hostingView)
    // Belt-and-suspenders for the global-hotkey path: activation triggered from deep
    // inside an async effect chain can lag a beat behind the calls above, so
    // re-assert on the next run loop turn too.
    DispatchQueue.main.async { [weak self, weak window, weak hostingView] in
      guard let window, let hostingView else { return }
      self?.activateAndFocus(window, hostingView: hostingView)
    }
  }

  private func activateAndFocus(_ window: NSWindow, hostingView: NSView) {
    NSApp.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    window.makeKey()
    window.makeFirstResponder(hostingView)
  }

  /// Centers the window on whichever screen the mouse is currently over (falling
  /// back to the main screen), so it shows up on the display the user is actually
  /// using.
  private func centerOnScreen(_ window: NSWindow) {
    let mouseLocation = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    else { return }

    let visibleFrame = screen.visibleFrame
    let origin = NSPoint(
      x: visibleFrame.midX - window.frame.width / 2,
      y: visibleFrame.midY - window.frame.height / 2
    )
    window.setFrameOrigin(origin)
  }

  private func dismiss() {
    window?.orderOut(nil)
    window = nil
  }

  func windowDidResignKey(_ notification: Notification) {
    // Clicking away (or Escape, via QuickAddView's onExitCommand) dismisses without
    // starting a download.
    store.send(.quickAdd(.presented(.cancelButtonTapped)))
  }
}
