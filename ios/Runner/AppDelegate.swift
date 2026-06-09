import Flutter
import Photos
import UIKit
import UserNotifications
import WatchConnectivity
import WidgetKit

// Committed deliberately (like Info.plist) so `flutter create` on the Codemagic
// runner leaves it untouched. Adds, on top of the default Flutter app delegate:
//   • APNs remote-notification registration (forwarded to Dart over the
//     `marginalia/push` channel → PushService persists the token).
//   • A WatchConnectivity bridge: the `marginalia/watch` channel receives the
//     daily phrase + reading stats from Dart and pushes them to the paired Apple
//     Watch via updateApplicationContext, where the watch app stores them in the
//     shared App Group and reloads its complications.
@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate
{
  // NOTE: FlutterAppDelegate ALREADY conforms to UNUserNotificationCenterDelegate
  // and implements the delegate methods, so we must NOT re-declare the conformance
  // (redundant-conformance error) and the delegate methods below must use
  // `override` (they override FlutterAppDelegate's).
  private var pushChannel: FlutterMethodChannel?
  private var watchChannel: FlutterMethodChannel?
  private var localNotifChannel: FlutterMethodChannel?
  private var instagramChannel: FlutterMethodChannel?
  private var photosChannel: FlutterMethodChannel?

  // Cold-launch buffer. When the app is launched (or resumed from terminated)
  // by tapping a push, `didReceive` can fire before the Flutter engine has
  // attached its `onNotificationTap` handler — the invokeMethod would be lost.
  // We stash the tapped notification's payload here and flush it the moment the
  // Dart side signals it is ready (via the `tapHandlerReady` method on the
  // `marginalia/push` channel).
  private var pendingTapUserInfo: [AnyHashable: Any]?
  private var tapHandlerReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Receive notification taps (and foreground presentation) ourselves so we
    // can deep-link. Safe to set here even though auth is requested later from
    // Dart — the delegate only needs to be in place before a notification is
    // delivered/tapped.
    UNUserNotificationCenter.current().delegate = self

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
      push.setMethodCallHandler { [weak self] call, result in
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
        case "tapHandlerReady":
          // Dart has attached its onNotificationTap handler. Flush any tap that
          // arrived during cold launch (terminated → tap → relaunch), then keep
          // the flag so future taps route immediately.
          self?.tapHandlerReady = true
          self?.flushPendingTap()
          result(nil)
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

      let localNotif = FlutterMethodChannel(
        name: "marginalia/localnotif",
        binaryMessenger: controller.binaryMessenger)
      localNotif.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "scheduleDailyPhrase":
          self?.scheduleDailyPhrase(call.arguments, result: result)
        case "cancelDailyPhrase":
          UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["daily_phrase"])
          result(true)
        case "scheduleReviewReminder":
          self?.scheduleReviewReminder(call.arguments, result: result)
        case "cancelReviewReminder":
          UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["review_due"])
          result(true)
        case "scheduleEveningReviewReminder":
          self?.scheduleEveningReviewReminder(call.arguments, result: result)
        case "cancelEveningReviewReminder":
          UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["review_evening"])
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      localNotifChannel = localNotif

      // Instagram Stories direct share. Dart renders the 9:16 highlight card to
      // a PNG and passes the bytes here; we drop them on the system pasteboard
      // under Instagram's documented sticker key and open the Stories composer
      // directly (instagram-stories://). `isAvailable` gates the dedicated
      // button so it only shows when Instagram is installed.
      let instagram = FlutterMethodChannel(
        name: "marginalia/instagram",
        binaryMessenger: controller.binaryMessenger)
      instagram.setMethodCallHandler { call, result in
        switch call.method {
        case "isAvailable":
          let url = URL(string: "instagram-stories://share")!
          result(UIApplication.shared.canOpenURL(url))
        case "shareToStories":
          guard
            let args = call.arguments as? [String: Any],
            let typed = args["image"] as? FlutterStandardTypedData
          else { result(false); return }
          let url = URL(
            string: "instagram-stories://share?source_application=marginalia")!
          guard UIApplication.shared.canOpenURL(url) else { result(false); return }
          let item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": typed.data
          ]
          let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
          ]
          UIPasteboard.general.setItems([item], options: options)
          UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      instagramChannel = instagram

      // Save an image (the rendered story PNG) to the user's photo library.
      // Add-only authorization (.addOnly on iOS 14+) so we never ask for full
      // library READ access. Requires NSPhotoLibraryAddUsageDescription.
      let photos = FlutterMethodChannel(
        name: "marginalia/photos",
        binaryMessenger: controller.binaryMessenger)
      photos.setMethodCallHandler { call, result in
        switch call.method {
        case "saveImage":
          guard
            let args = call.arguments as? [String: Any],
            let typed = args["bytes"] as? FlutterStandardTypedData
          else { result(false); return }
          let data = typed.data
          func performSave() {
            PHPhotoLibrary.shared().performChanges({
              let req = PHAssetCreationRequest.forAsset()
              req.addResource(with: .photo, data: data, options: nil)
            }) { ok, _ in
              DispatchQueue.main.async { result(ok) }
            }
          }
          if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
              if status == .authorized || status == .limited {
                performSave()
              } else {
                DispatchQueue.main.async { result(false) }
              }
            }
          } else {
            PHPhotoLibrary.requestAuthorization { status in
              if status == .authorized {
                performSave()
              } else {
                DispatchQueue.main.async { result(false) }
              }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      photosChannel = photos
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Clear the red app-icon badge whenever the app comes to the foreground, so a
  // push that bumped the badge doesn't leave a stale dot after the user has
  // already opened the app.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    UIApplication.shared.applicationIconBadgeNumber = 0

    // Force WidgetKit to rebuild EVERY widget's timeline whenever the app comes
    // to the foreground. The Dart side (widgetSyncProvider) re-writes the shared
    // App Group payload on resume and calls home_widget's updateWidget per kind,
    // but a belt-and-braces reloadAllTimelines() here guarantees both the home
    // and lock-screen widgets (ScriptaWidget + ScriptaStats, and any future
    // kind) actually re-render against the freshly saved data — the fix for
    // "widgets stay stale even after reopening the app".
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
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

  // ── Notification tap → deep link ────────────────────────────────────────────

  // Fired when the user TAPS a notification (banner, lock screen, or
  // Notification Center) — whether the app was in the foreground, background, or
  // terminated. `userInfo` is the APNs payload; the `send-push-notification`
  // edge function spreads its `data` object to the top level, so the custom
  // navigation keys (conversation_id, type, post_id) live directly on it.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    forwardTap(response.notification.request.content.userInfo)
    completionHandler()
  }

  // Show banner/sound even when a push arrives while the app is in the
  // foreground, so the user can still tap it to deep-link (otherwise iOS
  // suppresses foreground notifications entirely).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.alert, .badge, .sound])
  }

  // Sends the tapped notification's navigation data to Dart. The payload can
  // contain non-Flutter-serialisable APNs internals (e.g. the `aps` dictionary),
  // so we extract only the small set of keys the router understands into a clean
  // [String: String] dict. If Dart hasn't attached its handler yet (cold launch
  // from a terminated state), the tap is buffered and replayed on
  // `tapHandlerReady`.
  private func forwardTap(_ userInfo: [AnyHashable: Any]) {
    // The Ripasso reminders (morning + evening) carry `review: true` so a tap
    // deep-links straight to /review.
    let isReview = (userInfo["review"] as? Bool) == true
      || (userInfo["review"] as? NSNumber)?.boolValue == true
    let hasNavData = userInfo["conversation_id"] != nil
      || userInfo["post_id"] != nil
      || isReview
    guard hasNavData else { return }

    guard tapHandlerReady, let channel = pushChannel else {
      pendingTapUserInfo = userInfo
      return
    }

    var payload: [String: String] = [:]
    if let conversationId = userInfo["conversation_id"] as? String {
      payload["conversation_id"] = conversationId
    }
    if let postId = userInfo["post_id"] as? String {
      payload["post_id"] = postId
    }
    if let type = userInfo["type"] as? String {
      payload["type"] = type
    }
    if isReview {
      payload["review"] = "true"
    }

    channel.invokeMethod("onNotificationTap", arguments: payload)
  }

  // Replays a tap that arrived before the Dart handler was ready.
  private func flushPendingTap() {
    guard let userInfo = pendingTapUserInfo else { return }
    pendingTapUserInfo = nil
    forwardTap(userInfo)
  }

  // ── Daily phrase local notification ───────────────────────────────────────────

  // Schedules (or re-schedules) the repeating daily "frase del giorno" nudge.
  // Reuses the same UNUserNotificationCenter authorization already requested for
  // push, so no extra permission prompt is needed. The fixed "daily_phrase"
  // identifier means calling this on every launch simply replaces the pending
  // request rather than stacking duplicates.
  private func scheduleDailyPhrase(_ arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any]
    let hour = args?["hour"] as? Int ?? 9
    let minute = args?["minute"] as? Int ?? 0
    let title = args?["title"] as? String ?? "Scripta"
    let body = args?["body"] as? String ?? ""

    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["daily_phrase"])

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    var dc = DateComponents()
    dc.hour = hour
    dc.minute = minute
    let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)

    let request = UNNotificationRequest(
      identifier: "daily_phrase", content: content, trigger: trigger)
    center.add(request) { error in
      if let error = error {
        NSLog("scheduleDailyPhrase failed: \(error.localizedDescription)")
      }
    }
    result(true)
  }

  // ── Ripasso (spaced-repetition) reminder ──────────────────────────────────────

  // Schedules (or re-schedules) the repeating daily "Hai N highlight da
  // ripassare" nudge under the stable "review_due" identifier, parallel to
  // "daily_phrase". Reuses the same UNUserNotificationCenter authorization, so
  // there is no extra permission prompt. The due count is captured at schedule
  // time; re-scheduling on launch/foreground keeps it fresh, and the Dart side
  // cancels it when nothing is due.
  private func scheduleReviewReminder(_ arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any]
    let hour = args?["hour"] as? Int ?? 9
    let minute = args?["minute"] as? Int ?? 0
    let title = args?["title"] as? String ?? "Scripta"
    let body = args?["body"] as? String ?? ""

    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["review_due"])

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    // Payload so a future tap can deep-link to /review (follow-up wave).
    content.userInfo = ["review": true]

    var dc = DateComponents()
    dc.hour = hour
    dc.minute = minute
    let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)

    let request = UNNotificationRequest(
      identifier: "review_due", content: content, trigger: trigger)
    center.add(request) { error in
      if let error = error {
        NSLog("scheduleReviewReminder failed: \(error.localizedDescription)")
      }
    }
    result(true)
  }

  // Schedules (or re-schedules) the repeating EVENING "Did you do your review
  // today?" nudge under the stable "review_evening" identifier, parallel to
  // "review_due". Fires at 21:00 by default. The Dart side only schedules this
  // when the user has NOT reviewed today and cancels it the moment a session
  // starts, so it never nags someone who already did their ripasso. Like the
  // morning reminder, it carries `review: true` so a tap deep-links to /review.
  private func scheduleEveningReviewReminder(_ arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any]
    let hour = args?["hour"] as? Int ?? 21
    let minute = args?["minute"] as? Int ?? 0
    let title = args?["title"] as? String ?? "Scripta"
    let body = args?["body"] as? String ?? ""

    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["review_evening"])

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.userInfo = ["review": true]

    var dc = DateComponents()
    dc.hour = hour
    dc.minute = minute
    let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)

    let request = UNNotificationRequest(
      identifier: "review_evening", content: content, trigger: trigger)
    center.add(request) { error in
      if let error = error {
        NSLog("scheduleEveningReviewReminder failed: \(error.localizedDescription)")
      }
    }
    result(true)
  }
}
