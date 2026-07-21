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
/// `NSPanel`, and switches `NSApp`'s activation policy to `.regular` for the moment
/// it's shown (see `showIfNeeded`/`dismiss`) — both changes needed to reliably get
/// the window into a real key/active state when summoned from a global hotkey.
/// Diagnostic logging confirmed that part now works correctly (window key, app
/// active, right window). The remaining piece — SwiftUI's `@FocusState` actually
/// landing on the text field — is handled in `QuickAddView` itself; this class
/// deliberately does *not* also call `makeFirstResponder`/synthesize a click, since
/// those turned out to interfere with SwiftUI's own focus handling rather than help it.
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

    let hostingView = NSHostingView(
      rootView: QuickAddView(store: childStore) { [weak self] size in
        self?.resizeWindow(toContentSize: size)
      }
    )
    // Without this, the hosting view keeps whatever fixed frame we hand it below and
    // doesn't track the window's actual content area on later resizes, which is what
    // was leaving a sliver of the native titlebar background visible above the popup.
    hostingView.autoresizingMask = [.width, .height]
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
    // A `.titled` window's own chrome defaults to a light appearance regardless of
    // our SwiftUI content forcing `.colorScheme(.dark)` — that's a separate,
    // AppKit-level appearance. Forcing this too means any native titlebar remnant
    // renders dark and blends in, instead of showing up as a stray light bar.
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = hostingView
    window.delegate = self

    // `NSWindow(contentRect:styleMask:...)`'s `contentRect` is still interpreted as
    // "the area below the titlebar" even with `.fullSizeContentView` set, so the
    // initializer adds titlebar height on top of the size we asked for — leaving a
    // titlebar-height gap at the top where native chrome could show through.
    // `setContentSize` is titlebar-aware for `.fullSizeContentView` windows and
    // corrects that, so the window ends up exactly `fittingSize` with no leftover
    // gap.
    window.setContentSize(fittingSize)

    centerOnScreen(window)

    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  /// Resizes the window to match the SwiftUI content's actual rendered size (reported
  /// live via `QuickAddView`'s `onSizeChange`), keeping it anchored around its current
  /// center point so it grows/shrinks in place instead of drifting as the text changes.
  private func resizeWindow(toContentSize contentSize: CGSize) {
    guard let window else { return }
    let roundedSize = NSSize(width: contentSize.width.rounded(), height: contentSize.height.rounded())
    guard roundedSize.width > 0, roundedSize.height > 0 else { return }

    let currentFrame = window.frame
    guard currentFrame.size != roundedSize else { return }

    let center = NSPoint(x: currentFrame.midX, y: currentFrame.midY)
    // `setContentSize` (see the comment in `showIfNeeded`) rather than `setFrame`
    // with a manually computed size, so this stays exact as the window's titlebar
    // (still present, just hidden) keeps being accounted for correctly.
    window.setContentSize(roundedSize)
    window.setFrameOrigin(
      NSPoint(x: center.x - roundedSize.width / 2, y: center.y - roundedSize.height / 2)
    )
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
