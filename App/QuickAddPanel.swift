import AppFeature
import AppKit
import ComposableArchitecture
import QuickAddFeature
import SwiftUI

/// A borderless window that can still become key. Borderless `NSWindow`s return
/// `false` from `canBecomeKey` by default, which blocks keyboard input entirely —
/// this override is the standard fix, and is unrelated to (and doesn't reintroduce)
/// the earlier `@FocusState` timing bug fixed in `QuickAddView`.
private final class KeyableBorderlessWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

/// The popup that appears centered on screen when the global shortcut fires.
/// Presence is entirely driven by `AppFeature.State.quickAdd`: this class just
/// shows/hides an `NSWindow` to match, and turns "clicked away" into a cancel.
///
/// This is a fully `.borderless` window — no titlebar, so there's no native chrome
/// (traffic lights, titlebar background material, ...) to hide in the first place,
/// unlike an earlier version of this file that used a `.titled` window with its
/// titlebar hidden, which kept leaving a sliver of native chrome visible above the
/// popup no matter how it was configured. `NSApp`'s activation policy still switches
/// to `.regular` for the moment it's shown (see `showIfNeeded`/`dismiss`) to reliably
/// get the window into a real key/active state when summoned from a global hotkey.
/// The other piece needed for that — SwiftUI's `@FocusState` actually landing on the
/// text field — is handled in `QuickAddView` itself; this class deliberately does
/// *not* also call `makeFirstResponder`/synthesize a click, since those turned out to
/// interfere with SwiftUI's own focus handling rather than help it.
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
    // So the hosting view keeps tracking the window's actual content area (which is
    // the entire window for a borderless one) across later resizes.
    hostingView.autoresizingMask = [.width, .height]
    // `NSHostingView`/SwiftUI paint an opaque backing somewhere in their internal
    // layer hierarchy by default, which shows through as a light gray fill at the
    // corners *outside* the SwiftUI content's rounded `clipShape` — the window being
    // non-opaque with a clear background isn't enough, and neither was clearing just
    // the hosting view's own top-level layer background (some deeper internal layer
    // still painted it). Masking the hosting view's layer to the same rounded shape
    // clips everything within it — regardless of what any internal layer paints — at
    // the compositing level, which is a hard guarantee rather than another guess at
    // which specific layer is responsible.
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = .clear
    hostingView.layer?.cornerRadius = QuickAddView.cornerRadius
    hostingView.layer?.masksToBounds = true
    let fittingSize = hostingView.fittingSize
    hostingView.frame = NSRect(origin: .zero, size: fittingSize)

    let window = KeyableBorderlessWindow(
      contentRect: hostingView.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isMovableByWindowBackground = true
    window.level = .floating
    window.isOpaque = false
    window.backgroundColor = .clear
    // The native window shadow is computed from the window's rectangular frame, not
    // the rounded shape SwiftUI actually draws — that mismatch is what showed up as a
    // faint rectangular hairline right at the corners. `QuickAddView` already draws
    // its own shadow that follows the real rounded shape, so the native one is both
    // redundant and the actual source of the artifact; turn it off.
    window.hasShadow = false
    window.contentView = hostingView
    window.delegate = self

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
