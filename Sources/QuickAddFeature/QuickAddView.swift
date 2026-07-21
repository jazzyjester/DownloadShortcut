import AppKit
import ComposableArchitecture
import SwiftUI

public struct QuickAddView: View {
  @Bindable var store: StoreOf<QuickAddFeature>
  @FocusState private var isTextFieldFocused: Bool

  /// Reports the view's rendered content size after every layout pass, so the
  /// hosting `NSWindow` (which SwiftUI doesn't own or auto-resize) can be kept in
  /// sync as the text grows or shrinks. No-op by default so previews don't need it.
  var onSizeChange: (CGSize) -> Void = { _ in }

  public init(store: StoreOf<QuickAddFeature>, onSizeChange: @escaping (CGSize) -> Void = { _ in }) {
    self.store = store
    self.onSizeChange = onSizeChange
  }

  /// Also used by `QuickAddPanel` to mask the hosting `NSView`'s own layer to the
  /// same shape, as a backstop against AppKit/SwiftUI internals painting an opaque
  /// background outside this view's own `clipShape`.
  public static let cornerRadius: CGFloat = 28

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      TextField("Paste or type a URL…", text: $store.urlText, axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.white)
        .tint(.white)
        .lineLimit(3...10)
        .focused($isTextFieldFocused)
        .onSubmit { store.send(.submitButtonTapped) }

      // Live feedback as text changes, instead of only finding out it's invalid
      // after pressing Enter.
      if !store.urlText.isEmpty {
        HStack(alignment: .center, spacing: 10) {
          Label(
            store.isValid ? "Valid URL — press Enter to download" : "Doesn't look like a URL yet",
            systemImage: store.isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
          )
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(store.isValid ? Color(red: 0.4, green: 0.95, blue: 0.6) : Color(red: 1, green: 0.7, blue: 0.35))
          .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 8)

          if let pastedAt = store.pastedAt {
            Label(pastedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.white.opacity(0.55))
              .fixedSize()
              .padding(.horizontal, 9)
              .padding(.vertical, 4)
              .background(Capsule().fill(.white.opacity(0.08)))
              .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
          }
        }
      }

      if let validationError = store.validationError {
        Text(validationError)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.4))
      }
    }
    .padding(26)
    .frame(minWidth: 420, idealWidth: 640, maxWidth: 900, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .background(
      // A solid, opaque dark fill rather than a real vibrancy blur — the earlier
      // `.behindWindow` material composited with whatever was actually behind the
      // popup on screen (another window, a browser tab, ...), which read as stray
      // text/lines showing through rather than a deliberate glass effect. A subtle
      // top-to-bottom gradient keeps some depth without letting anything bleed
      // through; the only real transparency left is the four corners outside the
      // rounded rect, which is the intended "floating rounded window" look.
      LinearGradient(
        colors: [
          Color(red: 0.16, green: 0.16, blue: 0.19),
          Color(red: 0.09, green: 0.09, blue: 0.11),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        // A brighter hairline along the top fading to nothing lower down — the
        // classic "glass rim light" that sells the material as an actual pane of
        // glass rather than a flat dark rounded rectangle.
        .strokeBorder(
          LinearGradient(
            colors: [.white.opacity(0.5), .white.opacity(0.08)],
            startPoint: .top,
            endPoint: .bottom
          ),
          lineWidth: 1
        )
    )
    .shadow(color: .black.opacity(0.6), radius: 40, y: 18)
    // The panel is dark regardless of system appearance, so force this subtree to
    // render with light-on-dark text/controls for consistent contrast.
    .colorScheme(.dark)
    .background(
      GeometryReader { proxy in
        Color.clear.preference(key: QuickAddSizePreferenceKey.self, value: proxy.size)
      }
    )
    .onPreferenceChange(QuickAddSizePreferenceKey.self) { onSizeChange($0) }
    .onAppear {
      store.send(.onAppear)
      requestFocus()
    }
    // `.onAppear` can fire before the hosting panel has actually finished becoming
    // key (it's shown via manually-driven AppKit code, not SwiftUI's own window
    // lifecycle), so `@FocusState` set there doesn't reliably "stick". Re-apply it
    // whenever a window genuinely becomes key while this popup is showing.
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      requestFocus()
    }
    .onExitCommand { store.send(.cancelButtonTapped) }
  }

  /// Setting `@FocusState` synchronously inside `.onAppear` is a known SwiftUI
  /// timing issue — the view's focus wiring often isn't fully settled into the
  /// hierarchy at that exact instant, so the assignment silently doesn't stick.
  /// Deferring it by one run loop turn is the standard workaround.
  private func requestFocus() {
    DispatchQueue.main.async {
      isTextFieldFocused = true
    }
  }
}

private struct QuickAddSizePreferenceKey: PreferenceKey {
  static let defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
    value = nextValue()
  }
}

// Uses `PreviewProvider` rather than the `#Preview` macro: the macro depends on
// Xcode's PreviewsMacros plugin, which isn't available when building with only the
// Swift toolchain/Command Line Tools (as this package is designed to support).
struct QuickAddView_Previews: PreviewProvider {
  static var previews: some View {
    QuickAddView(
      store: Store(initialState: QuickAddFeature.State(urlText: "https://example.com/file.zip")) {
        QuickAddFeature()
      }
    )
  }
}
