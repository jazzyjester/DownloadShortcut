import AppKit
import ComposableArchitecture
import SwiftUI

public struct QuickAddView: View {
  @Bindable var store: StoreOf<QuickAddFeature>
  @FocusState private var isTextFieldFocused: Bool

  public init(store: StoreOf<QuickAddFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
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
        Label(
          store.isValid ? "Valid URL — press Enter to download" : "Doesn't look like a URL yet",
          systemImage: store.isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .font(.title3)
        .foregroundStyle(store.isValid ? Color.green : Color.orange)
      }

      if let validationError = store.validationError {
        Text(validationError)
          .font(.title3)
          .foregroundStyle(.red)
      }
    }
    .padding(28)
    .frame(width: 760, alignment: .leading)
    .frame(minHeight: 180, alignment: .top)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.27, green: 0.12, blue: 0.48),
          Color(red: 0.06, green: 0.36, blue: 0.56),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.18)))
    // The gradient is dark regardless of system appearance, so force this subtree
    // to render with light-on-dark text/controls for consistent contrast.
    .colorScheme(.dark)
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
    .onChange(of: isTextFieldFocused) { _, newValue in
      print("[QuickAddView] isTextFieldFocused changed to \(newValue)")
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
