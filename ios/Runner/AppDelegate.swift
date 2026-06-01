import Flutter
import UIKit
import UserNotifications
import WatchConnectivity

// Committed deliberately (like Info.plist) so `flutter create` on the Codemagic
// runner leaves it untouched. Adds, on top of the default Flutter app delegate:
//   • APNs remote-notification registration (forwarded to Dart over the
//     `marginalia/push` channel → PushService persists the token).
//   • A WatchConnectivity bridge: the `marginalia/watch` channel receives the
//     daily phrase + reading stats from Dart and pushes them to the paired Apple
//     Watch via updateApplicationContext, where the watch app stores them in the
//     shared App Group and reloads its complications.
@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var watchChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Activate WatchConnectivity so we can push context to the watch.
    if WCSession.isSupported() {
      let session = WCSession.default
      session.delegate = self
      session.activate()
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let push = FlutterMethodChannel(
        name: "marginalia/push",
        binaryMessenger: controller.binaryMessenger)
      push.setMethodCallHandler { call, result in
        switch call.method {
        case "register":
          UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
          ) { granted, _ in
            if granted {
              DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
              }
            }
            result(granted)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      pushChannel = push

      let watch = FlutterMethodChannel(
        name: "marginalia/watch",
        binaryMessenger: controller.binaryMessenger)
      watch.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "send":
          if let args = call.arguments as? [String: Any] {
            self?.sendToWatch(args)
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      watchChannel = watch
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ── Watch bridge ─────────────────────────────────────────────────────────────

  // Pushes the latest snapshot to the watch. updateApplicationContext keeps only
  // the most recent state (perfect for a complication) and is a no-op when no
  // watch is paired / the app isn't installed.
  private func sendToWatch(_ data: [String: Any]) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated else { return }
    do {
      try session.updateApplicationContext(data)
    } catch {
      NSLog("WatchConnectivity updateApplicationContext failed: \(error.localizedDescription)")
    }
  }

  // ── WCSessionDelegate (required) ──────────────────────────────────────────────

  func session(_ session: WCSession,
               activationDidCompleteWith activationState: WCSessionActivationState,
               error: Error?) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  // After a watch switch the default session deactivates; reactivate so future
  // context pushes keep working.
  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }

  // ── APNs ──────────────────────────────────────────────────────────────────────

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pushChannel?.invokeMethod("onToken", arguments: token)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs registration failed: \(error.localizedDescription)")
  }
}
