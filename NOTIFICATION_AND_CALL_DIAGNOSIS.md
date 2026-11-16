# Comprehensive Notification & Call Banner Diagnosis & Architecture Plan
**Project:** SecureCalc (Android & iOS)  
**Date:** November 16, 2026  
**Scope:** Push Notifications (APNs & FCM), CallKit & Call Banners, Multi-Notification Clearing on iOS, Android Heads-Up Call Notifications, and Background Isolate Synchronization.

---

## 1. Executive Summary

This document provides a thorough audit of the notification and calling subsystems in SecureCalc across both iOS and Android. It details every identified bug, architectural complexity, and platform-specific limitation, along with the exact step-by-step solutions to be implemented upon your approval.

### Primary Focus Areas
1. **iOS Multi-Notification Clearing:** When multiple notifications are delivered in the iOS Notification Center, tapping *any single notification* or opening the app currently leaves all other notifications lingering in the tray.
2. **Call Banners on Android:** High-priority incoming call banners often fail to appear as heads-up popups on Android 12, 13, 14, and 15 due to custom layout overrides (`isCustomNotification: true`) and Android 14 full-screen intent restrictions.
3. **CallKit & Audio Race Conditions on iOS:** CallKit lockscreen acceptance conflicts with delayed WebRTC audio session activation and socket reconnection.
4. **Missed Call Visibility:** Secret mode (`includesCallsInRecents: false`) prevents calls from appearing in native phone logs, but misses posting local notifications when a call ends while the app is in the background.
5. **Background Isolate Memory Separation:** The FCM background handler attempts to modify UI state variables (`CallHistoryViewState.onNewMissedCallReceived()`) across isolate boundaries where memory is not shared.

---

## 2. Issue #1: iOS Multi-Notification Clearing Failure (Deep Dive)

### The Problem
When multiple message notifications arrive on an iOS device (e.g., 5 unread messages from different chats), they accumulate in the iOS Notification Center / Lock Screen. When the user taps on **one** notification:
- iOS opens the app.
- Only the tapped notification disappears; **the remaining 4 notifications stay stuck in Notification Center**, and the app icon badge count remains out of sync.

### Root Cause Analysis
1. **UNUserNotificationCenter Delegate Hijacking:**
   - In `ios/Runner/AppDelegate.swift`, the app sets `UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate` inside `didFinishLaunchingWithOptions`.
   - Immediately afterward, `GeneratedPluginRegistrant.register(with: self)` runs, loading `flutter_local_notifications`.
   - `FlutterLocalNotificationsPlugin.m` internally executes `[[UNUserNotificationCenter currentNotificationCenter] setDelegate:self]`, **overwriting AppDelegate as the delegate**.
   - As a result, `AppDelegate`'s `userNotificationCenter(_:didReceive:withCompletionHandler:)` (which contains `center.removeAllDeliveredNotifications()`) **is never called by iOS** when tapping notifications.
2. **Missing `applicationDidBecomeActive` Lifecycle Handler:**
   - In iOS UIKit, the canonical, fail-safe trigger for clearing notifications when an app is opened is `applicationDidBecomeActive(_ application: UIApplication)`.
   - `AppDelegate.swift` currently **does not implement `applicationDidBecomeActive` at all**.
   - Because of this, whether the user taps a notification, taps the app icon, or switches back into the app, iOS never receives the command to clear the notification drawer.
3. **Duplicate Security MethodChannel Registrations:**
   - `AppDelegate.setupSecurityChannel` is called twice: once with `registrar(forPlugin: "SecurityChannelPlugin").messenger()` and once with `controller.binaryMessenger`. This can lead to dropped invocations of `clearAllNotifications`.

### Solution for iOS Multi-Notification Clearing
1. **Implement `applicationDidBecomeActive` in `AppDelegate.swift`:**
   ```swift
   override func applicationDidBecomeActive(_ application: UIApplication) {
     super.applicationDidBecomeActive(application)
     // Guarantees all delivered notifications and badges are wiped immediately
     // the instant the app enters the foreground from ANY notification tap or icon launch.
     UNUserNotificationCenter.current().removeAllDeliveredNotifications()
     UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
     if #available(iOS 16.0, *) {
       UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
     } else {
       UIApplication.shared.applicationIconBadgeNumber = 0
     }
   }
   ```
2. **Listen to `UIApplication.didBecomeActiveNotification` Internally:**
   Add a notification observer in `AppDelegate` so notification clearing runs on the main thread even if delegate methods are intercepted by third-party plugins.
3. **Synchronize in Dart (`app.dart` & `push_service.dart`):**
   Ensure `PushService.instance.clearAllNotifications()` is triggered whenever:
   - `AppLifecycleState.resumed` occurs.
   - `FirebaseMessaging.onMessageOpenedApp` fires.
   - `FirebaseMessaging.getInitialMessage` resolves.
   - `onDidReceiveNotificationResponse` fires in `flutter_local_notifications`.

---

## 3. Issue #2: Android Call Banner & CallKit Issues (Deep Dive)

### The Problem
On Android 12 through Android 15:
- Incoming calls often fail to show a top Heads-Up floating banner (Heads-Up Notification / HUN) when the phone is unlocked.
- On the lock screen, calls either show as a standard text notification or fail to turn on the screen with full-screen incoming call UI.

### Root Cause Analysis
1. **`isCustomNotification: true` in `AndroidParams`:**
   - In `lib/src/features/chat/domain/services/call_kit_service.dart`, `AndroidParams` specifies `isCustomNotification: true`.
   - Custom `RemoteViews` layouts in Android notifications have severe compatibility issues across custom manufacturer skins (Samsung OneUI, Xiaomi HyperOS/MIUI, Oppo/Vivo ColorOS). They frequently fail to expand as a Heads-Up banner and get demoted to the notification shade.
   - Switching to `isCustomNotification: false` lets Android use the native system Telecom/CallStyle layout, which is guaranteed by the OS to pop up over running apps with standard green Accept and red Decline action buttons.
2. **Android 14+ `USE_FULL_SCREEN_INTENT` Restrictions:**
   - On Android 14+ (API level 34+), the `USE_FULL_SCREEN_INTENT` permission is NOT automatically granted to apps unless categorized as a dialer or granted manually in Settings > Special App Access.
   - When full-screen intent is blocked by the OS, Android relies *exclusively* on high-priority heads-up notifications. If the notification channel is not configured with `Importance.max` and `VISIBILITY_PUBLIC`, the call rings silently in the status bar without a visual banner.
3. **Notification Channel Importance & Audio Attributes:**
   - Android requires call notification channels to have `audioAttributes` with `AudioAttributes.USAGE_NOTIFICATION_RINGTONE`. Without this, "Do Not Disturb" (DND) or system ring volume settings can completely suppress the call banner popup.

### Solution for Android Call Banners
1. Set `isCustomNotification: false` in `call_kit_service.dart`.
2. Configure AndroidParams with:
   - `isShowFullLockedScreen: true`
   - `isCustomNotification: false`
   - `ringtonePath: 'system_ringtone_default'`
   - `actionColor: '#4CAF50'`
3. Explicitly verify that the Android incoming call notification channel has `Importance.max` and `LockscreenVisibility.public`.

---

## 4. Issue #3: iOS CallKit & VoIP Audio Race Conditions

### The Problem
- When answering an incoming call from the native iOS CallKit lockscreen, audio occasionally does not connect (one-way audio or silence).
- Missed calls do not appear anywhere because the app hides calls from the iOS Phone app recents (`includesCallsInRecents: false`), but fails to post an in-app missed call notification.

### Root Cause Analysis
1. **Audio Session Ownership Conflict:**
   - `configureAudioSession: false` is used so `AudioRouteManager.swift` manages routing.
   - When the user taps Accept on CallKit, iOS fires `didActivateAudioSession`. At that exact moment, Dart is still establishing the WebRTC peer connection and reconnecting the socket. If `RTCAudioSession.audioSessionDidActivate` is called before WebRTC creates its audio tracks, WebRTC fails to bind to the active hardware audio session.
2. **No Missed Call Alert in Secret Mode:**
   - For privacy and stealth, `includesCallsInRecents: false` prevents SecretCalc calls from appearing in the iOS Phone app.
   - However, when a call is cancelled or missed while the phone is locked, CallKit dismisses silently. The user is never alerted that they missed a call.

### Solution for iOS CallKit & VoIP
1. **Audio Handshake Synchronization:**
   - In `AppDelegate.swift`, ensure `RTCAudioSession.sharedInstance().isAudioEnabled = true` is accompanied by an explicit category configuration (`.playAndRecord` with `.allowBluetooth` and `.defaultToSpeaker`).
   - In `call_service.dart`, call `reapplyRoute()` immediately upon transitioning to `CallState.active`.
2. **Missed Call Local Notification:**
   - When an incoming call ends with status `missed`, `cancelled`, or `busy`, display a local notification: `"Missed call from [Caller Name]"` with payload linking directly to the chat conversation.

---

## 5. Issue #4: Background Isolate Memory & Architecture Simplification

### The Problem
In `lib/src/features/chat/domain/services/push_service.dart`:
```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  ...
  if (status == 'missed' || status == 'rejected' || status == 'busy') {
    CallHistoryViewState.onNewMissedCallReceived(); // BUG: Isolated memory!
  }
}
```
1. **Isolated Heap:** The background handler runs in a separate Dart isolate. `CallHistoryViewState` static variables only exist in the background isolate, which is destroyed immediately after execution. The main UI isolate never sees this state.
2. **Channel Creation Overhead:** `push_service.dart` calls `createNotificationChannel` on every single message in `_showNotificationWithDetails`. Channels only need to be created once during initialization.
3. **Fragmented Data Keys:** Incoming payloads use inconsistent key names (`chat_id`, `chatId`, `chat_head_id`, `chatHeadId`, `id`, `sender_id`, `senderId`, `sender_user_id`, `from_id`). Parsing must be centralized.

### Solution
1. Store missed calls in persistent storage (`LocalChatStorage` or SQLite/SharedPreferences) so the main UI loads them reliably upon resume.
2. Initialize notification channels once during `PushService.init()` instead of on every incoming message.
3. Centralize payload normalization in helper methods.

---

## 6. Proposed Code Changes (File by File)

### 1. `ios/Runner/AppDelegate.swift`
- Add `applicationDidBecomeActive(_:)` with `center.removeAllDeliveredNotifications()`, `center.removeAllPendingNotificationRequests()`, and badge zeroing.
- Add notification observer for `UIApplication.didBecomeActiveNotification`.
- Prevent duplicate `setupSecurityChannel` registrations by attaching only once.
- Enhance `clearAllNotifications` MethodChannel handler to clear delivered and pending notifications synchronously and reset badge.

### 2. `lib/src/features/chat/domain/services/call_kit_service.dart`
- Change `isCustomNotification` to `false` in `AndroidParams` so Android uses the native system CallStyle incoming call banner with standard floating controls.
- Ensure `includesCallsInRecents: false` remains intact for privacy.
- Add clean error handling and timeout safeguards for incoming call presentation.

### 3. `lib/src/features/chat/domain/services/push_service.dart`
- In `clearAllNotifications()`:
  - Cancel all local notifications via `_local.cancelAll()`.
  - Zero the badge via `AppBadgePlus` and native channel.
  - Invoke native `clearAllNotifications` via MethodChannel.
- In `_ensureLocalInit()`:
  - Create channels once during app launch.
- In `firebaseMessagingBackgroundHandler`:
  - If a call ends with `missed` or `cancelled`, show a clean local notification: `"Missed call from [Caller Name]"`.
- Remove broken cross-isolate static calls.

### 4. `lib/src/app.dart`
- In `didChangeAppLifecycleState`:
  - When `AppLifecycleState.resumed`: call `PushService.instance.clearAllNotifications()`.
  - When entering foreground via notification tap: ensure all delivered notifications are wiped.

---

## 7. Verification & Testing Checklist

Once you review and approve this plan, we will execute the implementation and verify the following test cases:

| Test Case | Expected Behavior |
| :--- | :--- |
| **iOS Multi-Notification Clear** | Send 3 messages to iOS device. Tap on 1 notification. App opens and **all 3 notifications are removed from Notification Center**; badge is set to 0. |
| **iOS App Icon Open Clear** | Send 2 messages to iOS device while locked. Unlock and tap the Calculator app icon. Notification Center is completely cleared. |
| **Android Call Heads-Up Banner** | Initiate an audio/video call while recipient is using another app on Android. A floating system call banner appears at the top of the screen with Accept and Decline buttons. |
| **Android Lock Screen Call** | Initiate a call while Android screen is off. Screen turns on and displays full-screen incoming call UI. |
| **Missed Call Alert** | Caller rings and hangs up before callee answers. Callee receives a clean "Missed call from [Name]" notification. |
| **Calculator Stealth Mode** | Locked Calculator mode does not display chat details or call overlays until passcode is unlocked. |

---

> [!NOTE]
> Please review this diagnosis and plan. Whenever you are ready, reply **"proceed"** and we will implement the entire solution seamlessly across both Android and iOS!
