import AppKit
import ComposableArchitecture
import UserNotifications

/// The user-facing "a download just finished" feedback: a system notification and/or
/// a sound, both optional per Settings.
@DependencyClient
public struct CompletionFeedbackClient: Sendable {
  public var requestAuthorization: @Sendable () async -> Void
  public var notifyDownloadFinished: @Sendable (_ fileName: String) async -> Void
  public var playSound: @Sendable () -> Void
}

extension CompletionFeedbackClient: DependencyKey {
  public static let liveValue = CompletionFeedbackClient(
    requestAuthorization: {
      guard isRunningInsideAppBundle else { return }
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    },
    notifyDownloadFinished: { fileName in
      guard isRunningInsideAppBundle else { return }
      let content = UNMutableNotificationContent()
      content.title = "Download Finished"
      content.body = fileName
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      try? await UNUserNotificationCenter.current().add(request)
    },
    playSound: {
      NSSound(named: "Glass")?.play()
    }
  )
}

/// `UNUserNotificationCenter.current()` throws an uncaught `NSException` (not a
/// catchable Swift error) when the process isn't running from a real, code-signed
/// `.app` bundle — e.g. a plain `swift run` executable, which has no bundle
/// identifier. Guard against that instead of crashing; a proper Xcode-built `.app`
/// always has one.
private var isRunningInsideAppBundle: Bool {
  Bundle.main.bundleIdentifier != nil
}

extension DependencyValues {
  public var completionFeedbackClient: CompletionFeedbackClient {
    get { self[CompletionFeedbackClient.self] }
    set { self[CompletionFeedbackClient.self] = newValue }
  }
}
