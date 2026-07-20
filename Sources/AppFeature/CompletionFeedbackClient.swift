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
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    },
    notifyDownloadFinished: { fileName in
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

extension DependencyValues {
  public var completionFeedbackClient: CompletionFeedbackClient {
    get { self[CompletionFeedbackClient.self] }
    set { self[CompletionFeedbackClient.self] = newValue }
  }
}
