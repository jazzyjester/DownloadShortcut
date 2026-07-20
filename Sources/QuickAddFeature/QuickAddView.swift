import ComposableArchitecture
import SwiftUI

public struct QuickAddView: View {
  @Bindable var store: StoreOf<QuickAddFeature>
  @FocusState private var isTextFieldFocused: Bool

  public init(store: StoreOf<QuickAddFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Paste or type a URL…", text: $store.urlText, axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 22))
        .lineLimit(3...10)
        .focused($isTextFieldFocused)
        .onSubmit { store.send(.submitButtonTapped) }

      if let validationError = store.validationError {
        Text(validationError)
          .font(.title3)
          .foregroundStyle(.red)
      }
    }
    .padding(24)
    .frame(width: 640, alignment: .leading)
    .frame(minHeight: 160, alignment: .top)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
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
