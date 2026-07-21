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

  private let cornerRadius: CGFloat = 22

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
      ZStack {
        // Real AppKit vibrancy (`.hudWindow`, the same material behind Spotlight's
        // and Notification Center's panels) rather than a SwiftUI `Material` fill —
        // it reads as genuinely dark, frosted glass instead of a tinted gray blur.
        // Needs the hosting NSWindow to be non-opaque with a clear background (set
        // in QuickAddPanel) for the blur to actually composite with the desktop.
        VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        Color.black.opacity(0.45)
      }
    )
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

/// Bridges `NSVisualEffectView` into SwiftUI so the popup can use the same real,
/// system-level vibrancy/blur materials AppKit panels like Spotlight use, rather
/// than SwiftUI's own (visually flatter) `Material` types.
private struct VisualEffectBackground: NSViewRepresentable {
  var material: NSVisualEffectView.Material
  var blendingMode: NSVisualEffectView.BlendingMode

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blendingMode
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = material
    nsView.blendingMode = blendingMode
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
