import AppKit
import ComposableArchitecture
import UserNotifications

/// The user-facing "a download just finished" feedback: a system notification and/or
/// a sound, both optional per Settings, plus a stream of which file the user clicked a
/// notification for (so it can be revealed in Finder).
@DependencyClient
public struct CompletionFeedbackClient: Sendable {
  public var requestAuthorization: @Sendable () async -> Void
  public var notifyDownloadFinished: @Sendable (_ fileName: String, _ fileURL: URL?) async -> Void
  public var playSound: @Sendable () -> Void
  public var notificationClicked: @Sendable () -> AsyncStream<URL> = { .finished }
}

extension CompletionFeedbackClient: DependencyKey {
  public static let liveValue = CompletionFeedbackClient(
    requestAuthorization: {
      guard isRunningInsideAppBundle else { return }
      UNUserNotificationCenter.current().delegate = notificationDelegate
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    },
    notifyDownloadFinished: { fileName, fileURL in
      guard isRunningInsideAppBundle else { return }
      let content = UNMutableNotificationContent()
      content.title = "Download Finished"
      content.body = fileName
      if let fileURL {
        content.userInfo = [notificationFileURLKey: fileURL.absoluteString]
      }
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      try? await UNUserNotificationCenter.current().add(request)
    },
    playSound: {
      NSSound(named: "Glass")?.play()
    },
    notificationClicked: {
      AsyncStream { continuation in
        notificationDelegate.onClicked = { fileURL in
          continuation.yield(fileURL)
        }
      }
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

private let notificationFileURLKey = "fileURL"

/// Bridges `UNUserNotificationCenterDelegate` click callbacks into `notificationClicked`'s
/// `AsyncStream`, the same closure-to-stream pattern `HotkeyClient` uses for its Carbon
/// callback. A single long-lived instance, since the app only ever wants one delegate
/// and one active subscriber for the lifetime of the process.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  var onClicked: (@Sendable (URL) -> Void)?

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let urlString = response.notification.request.content.userInfo[notificationFileURLKey] as? String,
      let fileURL = URL(string: urlString)
    {
      onClicked?(fileURL)
    }
    completionHandler()
  }

  // Without this, notifications are silently dropped while the app is frontmost
  // (e.g. right after a download finishes and the tray menu is open).
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

private let notificationDelegate = NotificationDelegate()

extension DependencyValues {
  public var completionFeedbackClient: CompletionFeedbackClient {
    get { self[CompletionFeedbackClient.self] }
    set { self[CompletionFeedbackClient.self] = newValue }
  }
}
