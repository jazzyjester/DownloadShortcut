import ComposableArchitecture
import HotkeyClient
@preconcurrency import KeyboardShortcuts
import SwiftUI

public struct SettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  public init(store: StoreOf<SettingsFeature>) {
    self.store = store
  }

  public var body: some View {
    Form {
      Section("Shortcut") {
        LabeledContent("Global shortcut") {
          KeyboardShortcuts.Recorder(for: .quickDownload)
        }
      }

      Section("Downloads") {
        Stepper(
          "Max concurrent downloads: \(store.settings.maxConcurrentDownloads)",
          value: Binding(
            get: { store.settings.maxConcurrentDownloads },
            set: { store.send(.maxConcurrentDownloadsChanged($0)) }
          ),
          in: 1...10
        )

        Toggle(
          "Notify when a download finishes",
          isOn: Binding(
            get: { store.settings.notifyOnCompletion },
            set: { store.send(.notifyOnCompletionToggleChanged($0)) }
          )
        )

        Toggle(
          "Play a sound when a download finishes",
          isOn: Binding(
            get: { store.settings.playSoundOnCompletion },
            set: { store.send(.playSoundToggleChanged($0)) }
          )
        )
      }

      Section("General") {
        Toggle(
          "Launch DownloadShortcut at login",
          isOn: Binding(
            get: { store.isLaunchAtLoginEnabled },
            set: { store.send(.launchAtLoginToggleChanged($0)) }
          )
        )
        if let launchAtLoginError = store.launchAtLoginError {
          Text(launchAtLoginError)
            .font(.caption)
            .foregroundStyle(.red)
        }

        Button("Clear Download History", role: .destructive) {
          store.send(.clearHistoryButtonTapped)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 360)
    .onAppear { store.send(.onAppear) }
  }
}

// See QuickAddView.swift for why this uses `PreviewProvider` instead of `#Preview`.
struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView(
      store: Store(initialState: SettingsFeature.State()) {
        SettingsFeature()
      }
    )
  }
}
