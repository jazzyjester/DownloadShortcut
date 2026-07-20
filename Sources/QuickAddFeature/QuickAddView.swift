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
      isTextFieldFocused = true
    }
    .onExitCommand { store.send(.cancelButtonTapped) }
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
