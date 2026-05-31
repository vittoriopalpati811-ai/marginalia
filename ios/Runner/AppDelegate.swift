import Flutter
import UIKit
import UserNotifications

// Committed deliberately (like Info.plist) so `flutter create` on the Codemagic
// runner leaves it untouched. Adds APNs remote-notification registration on top
// of the default Flutter app delegate and forwards the device token to Dart
// over the `marginalia/push` method channel, where PushService persists it to
// the Supabase `device_tokens` table.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pushChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "marginalia/push",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
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
      pushChannel = channel
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called by iOS once APNs returns the device token. Forward the hex string to
  // Dart; PushService upserts it into device_tokens (platform = "ios").
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
