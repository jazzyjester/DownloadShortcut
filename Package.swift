// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "DownloadShortcut",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "AppFeature", targets: ["AppFeature"])
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
    // Pinned below 1.16.0: that version (and 2.x) introduced `#Preview` blocks in
    // Recorder.swift, which need Xcode's PreviewsMacros plugin and fail to compile
    // with only Command Line Tools. 1.15.0 has the same Recorder/onKeyUp APIs used
    // here. Bump this once building against a machine with full Xcode is confirmed.
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", "1.15.0"..<"1.16.0"),
  ],
  targets: [
    // MARK: - Models

    .target(
      name: "SharedModels",
      dependencies: [
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
      ]
    ),

    // MARK: - Dependency clients

    .target(
      name: "ClipboardClient",
      dependencies: [
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
      ]
    ),
    .target(
      name: "HotkeyClient",
      dependencies: [
        "ClipboardClient",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        "KeyboardShortcuts",
      ]
    ),
    .target(
      name: "DownloadClient",
      dependencies: [
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
      ]
    ),
    .target(
      name: "HistoryClient",
      dependencies: [
        "SharedModels",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .target(
      name: "FileActionsClient",
      dependencies: [
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
      ]
    ),

    // MARK: - Features

    .target(
      name: "QuickAddFeature",
      dependencies: [
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
      ]
    ),
    .target(
      name: "DownloadQueueFeature",
      dependencies: [
        "SharedModels",
        "DownloadClient",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .target(
      name: "StatusBarFeature",
      dependencies: [
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
      ]
    ),
    .target(
      name: "HistoryFeature",
      dependencies: [
        "SharedModels",
        "HistoryClient",
        "FileActionsClient",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .target(
      name: "SettingsFeature",
      dependencies: [
        "SharedModels",
        "HotkeyClient",
        "KeyboardShortcuts",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .target(
      name: "AppFeature",
      dependencies: [
        "SharedModels",
        "ClipboardClient",
        "FileActionsClient",
        "HotkeyClient",
        "HistoryClient",
        "QuickAddFeature",
        "DownloadQueueFeature",
        "StatusBarFeature",
        "HistoryFeature",
        "SettingsFeature",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),

    // MARK: - App shell

    // The AppKit/SwiftUI glue in App/ (status item, popup panel, app delegate) is
    // also compiled as a plain SwiftPM executable, purely so `swift build`/`swift run`
    // can type-check and run it without Xcode. XcodeGen's project.yml compiles the
    // same files again as a real .app target (with Info.plist/entitlements/signing)
    // for distribution — the two builds are independent and don't conflict.
    // Just "AppFeature": it transitively links every other target this needs
    // (QuickAddFeature, StatusBarFeature, SettingsFeature, HistoryFeature,
    // SharedModels, ComposableArchitecture, ...). See the testing skill's note on
    // not relinking transitive dependencies.
    .executableTarget(
      name: "App",
      dependencies: [
        "AppFeature"
      ],
      path: "App",
      exclude: [
        "Info.plist",
        "DownloadShortcut.entitlements",
      ]
    ),

    // MARK: - Tests

    // "AppFeature" alone is enough: it transitively links every other target in this
    // package (and ComposableArchitecture), so relinking them here would duplicate
    // symbols. See the testing skill's "Do not link transitive dependencies" note.
    .testTarget(
      name: "DownloadShortcutTests",
      dependencies: [
        "AppFeature"
      ]
    ),
  ]
)
