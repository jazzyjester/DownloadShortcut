import AppKit
import ComposableArchitecture
import HotkeyClient
@preconcurrency import KeyboardShortcuts
import SwiftUI

/// A tabbed preferences window (General / Shortcut / Downloads / About), matching
/// the classic macOS Settings pattern (e.g. Safari, Mail) rather than one long form —
/// easier to scan and leaves room to grow without the window turning into a wall of
/// controls.
public struct SettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  public init(store: StoreOf<SettingsFeature>) {
    self.store = store
  }

  public var body: some View {
    TabView {
      generalTab
        .tabItem { Label("General", systemImage: "gearshape") }

      shortcutTab
        .tabItem { Label("Shortcut", systemImage: "keyboard") }

      downloadsTab
        .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

      aboutTab
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 480, height: 460)
    .onAppear { store.send(.onAppear) }
  }

  private var generalTab: some View {
    Form {
      Section {
        ToggleRow(
          title: "Launch at login",
          subtitle: "Start DownloadShortcut automatically when you sign in.",
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

        ToggleRow(
          title: "Skip the popup when possible",
          subtitle: "Downloads immediately if the clipboard already has a valid URL; falls back to the popup otherwise.",
          isOn: Binding(
            get: { store.settings.autoDownloadWhenClipboardHasValidURL },
            set: { store.send(.autoDownloadToggleChanged($0)) }
          )
        )
      }
    }
    .formStyle(.grouped)
  }

  private var shortcutTab: some View {
    Form {
      Section {
        LabeledContent("Open quick download") {
          KeyboardShortcuts.Recorder(for: .quickDownload)
        }
      } footer: {
        Text("Press this shortcut anywhere on your Mac to capture a URL from your clipboard and start downloading.")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var downloadsTab: some View {
    Form {
      Section {
        Stepper(
          "Max concurrent downloads: \(store.settings.maxConcurrentDownloads)",
          value: Binding(
            get: { store.settings.maxConcurrentDownloads },
            set: { store.send(.maxConcurrentDownloadsChanged($0)) }
          ),
          in: 1...10
        )
      }

      Section {
        ToggleRow(
          title: "Notify when a download finishes",
          subtitle: "Shows a notification you can click to reveal the file in Finder.",
          isOn: Binding(
            get: { store.settings.notifyOnCompletion },
            set: { store.send(.notifyOnCompletionToggleChanged($0)) }
          )
        )
        ToggleRow(
          title: "Play a sound when a download finishes",
          subtitle: nil,
          isOn: Binding(
            get: { store.settings.playSoundOnCompletion },
            set: { store.send(.playSoundToggleChanged($0)) }
          )
        )
      }

      Section {
        Button("Clear Download History…", role: .destructive) {
          store.send(.clearHistoryButtonTapped)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var aboutTab: some View {
    VStack(spacing: 14) {
      Spacer(minLength: 4)

      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

      VStack(spacing: 4) {
        Text(appName)
          .font(.title.bold())
        Text(versionString)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Text(
        "DownloadShortcut turns your clipboard into a download queue: press a shortcut "
          + "anywhere on your Mac, confirm the link, and the file lands in your Downloads "
          + "folder in seconds — no browser, no waiting for a page to load."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: 380)

      VStack(alignment: .leading, spacing: 10) {
        FeatureRow(
          systemImage: "keyboard",
          text: "Works system-wide from a global keyboard shortcut you choose."
        )
        FeatureRow(
          systemImage: "doc.on.clipboard",
          text: "Finds and fixes up the URL in whatever you last copied automatically."
        )
        FeatureRow(
          systemImage: "arrow.down.circle",
          text: "Runs several downloads at once, with live progress in the menu bar."
        )
        FeatureRow(
          systemImage: "bell",
          text: "Notifies you when a download finishes — click it to reveal the file in Finder."
        )
      }
      .frame(maxWidth: 380, alignment: .leading)

      Spacer(minLength: 4)

      if let copyright {
        Text(copyright)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
  }

  private var appName: String {
    Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "DownloadShortcut"
  }

  /// Falls back gracefully when running as a plain `swift run` executable outside a
  /// real bundle (as this package supports for sandbox-only verification) — there's
  /// no `CFBundleShortVersionString`/`CFBundleVersion` to read in that case.
  private var versionString: String {
    guard
      let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    else { return "Development Build" }
    return "Version \(shortVersion) (\(build))"
  }

  private var copyright: String? {
    Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
  }
}

/// A toggle with an optional secondary line of explanatory text underneath — the
/// same "title + caption" pattern macOS's own System Settings uses for anything
/// whose effect isn't obvious from the title alone.
private struct ToggleRow: View {
  let title: String
  let subtitle: String?
  @Binding var isOn: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Toggle(title, isOn: $isOn)
      if let subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
  }
}

/// One line of the About tab's feature list: a small leading glyph plus text,
/// wrapped over multiple lines if needed rather than truncating.
private struct FeatureRow: View {
  let systemImage: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(text)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
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
