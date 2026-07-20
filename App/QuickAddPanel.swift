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
/// shown from a global hotkey rather than a normal in-app click. Titled windows
/// behave normally here with no special-casing needed.
///
/// The other half of that fix: `.accessory` (`LSUIElement`) apps can have
/// `NSApp.activate(ignoringOtherApps:)` silently ignored by macOS when it's called
/// from a background-triggered context like a global hotkey — regardless of how
/// correctly/promptly it's called — where a `.regular` app's activation request
/// would be honored normally. This is a documented pattern used by similar
/// hotkey-summoned utilities (Alfred, Raycast, LaunchBar, …): switch to `.regular`
/// for the moment the window is shown (briefly showing a Dock icon), and back to
/// `.accessory` once it's dismissed.
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

    NSApp.setActivationPolicy(.regular)

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
    print("[QuickAddPanel] before activateAndFocus: NSApp.isActive=\(NSApp.isActive) policy=\(NSApp.activationPolicy())")
    activateAndFocus(window, hostingView: hostingView, tag: "immediate")
    // Belt-and-suspenders for the global-hotkey path: activation triggered from deep
    // inside an async effect chain can lag a beat behind the calls above, so
    // re-assert on the next run loop turn too.
    DispatchQueue.main.async { [weak self, weak window, weak hostingView] in
      guard let window, let hostingView else { return }
      self?.activateAndFocus(window, hostingView: hostingView, tag: "deferred")
    }
  }

  private func activateAndFocus(_ window: NSWindow, hostingView: NSView, tag: String) {
    NSApp.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    window.makeKey()
    window.makeFirstResponder(hostingView)
    simulateClickToFocus(window)
    print(
      """
      [QuickAddPanel] after activateAndFocus(\(tag)): \
      NSApp.isActive=\(NSApp.isActive) \
      policy=\(NSApp.activationPolicy()) \
      window.isKeyWindow=\(window.isKeyWindow) \
      window.isMainWindow=\(window.isMainWindow) \
      NSApp.keyWindow===thisWindow=\(NSApp.keyWindow === window) \
      window.firstResponder=\(String(describing: window.firstResponder))
      """
    )
  }

  /// Feeds a synthetic click directly into our own window — not a system-level
  /// `CGEvent` (which would need Accessibility permission, since posting into the
  /// global HID event stream is gated regardless of which window it targets), just
  /// an `NSEvent` constructed and handed to `window.sendEvent(_:)` in-process. This
  /// goes through the exact same hit-testing/first-responder code path a real click
  /// does, as a last-resort fallback in case that path succeeds where directly
  /// calling `makeKey`/`makeFirstResponder` above hasn't reliably.
  private func simulateClickToFocus(_ window: NSWindow) {
    // Aimed at the text field's likely position: horizontally centered, and near
    // the top (just below the view's top padding) since the field is the first,
    // top-aligned element in the popup regardless of how many lines its content
    // ends up wrapping to.
    let clickPoint = NSPoint(x: window.frame.width / 2, y: max(window.frame.height - 50, 20))
    let timestamp = ProcessInfo.processInfo.systemUptime

    guard
      let mouseDown = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: clickPoint,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      ),
      let mouseUp = NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: clickPoint,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      )
    else { return }

    window.sendEvent(mouseDown)
    window.sendEvent(mouseUp)
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
    NSApp.setActivationPolicy(.accessory)
  }

  func windowDidResignKey(_ notification: Notification) {
    // Clicking away (or Escape, via QuickAddView's onExitCommand) dismisses without
    // starting a download.
    store.send(.quickAdd(.presented(.cancelButtonTapped)))
  }
}
