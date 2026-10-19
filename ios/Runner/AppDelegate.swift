import Flutter
import UIKit
import Security
import UserNotifications
import FirebaseCore
import FirebaseMessaging

// MARK: - Keychain Helper

class KeychainHelper {
  static let service = "com.shis.securecalc.device_id"
  static let account = "hardware_device_id"

  static func save(_ value: String) {
    guard let data = value.data(using: .utf8) else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)

    var saveQuery = query
    saveQuery[kSecValueData as String] = data
    saveQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

    SecItemAdd(saveQuery as CFDictionary, nil)
  }

  static func load() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var dataTypeRef: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

    if status == errSecSuccess,
       let data = dataTypeRef as? Data,
       let id = String(data: data, encoding: .utf8),
       !id.isEmpty {
      return id
    }
    return nil
  }
}

// MARK: - App Delegate

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    application.registerForRemoteNotifications()

    if let controller = window?.rootViewController as? FlutterViewController {
      AppDelegate.setupSecurityChannel(with: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[Push iOS] Failed to register for remote notifications: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  static func setupSecurityChannel(with messenger: FlutterBinaryMessenger) {
    let securityChannel = FlutterMethodChannel(
      name: "com.shis.securecalc/security",
      binaryMessenger: messenger
    )

    securityChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getSystemDeviceId":
        if let persistentId = KeychainHelper.load() {
          result(persistentId)
          return
        }

        let vendorId = UIDevice.current.identifierForVendor?.uuidString
          .replacingOccurrences(of: "-", with: "")
          .lowercased() ?? ""

        let manufacturer = "apple"
        let model = AppDelegate.getDeviceModel()
          .lowercased()
          .replacingOccurrences(of: " ", with: "")

        let hardwareId = !vendorId.isEmpty ? "\(manufacturer)\(model)_\(vendorId)" : "\(manufacturer)\(model)"

        if !hardwareId.isEmpty {
          KeychainHelper.save(hardwareId)
        }

        result(hardwareId)

      case "setSecureFlag":
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static private func getDeviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)

    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { result, element in
      guard let value = element.value as? Int8, value != 0 else { return result }
      return result + String(UnicodeScalar(UInt8(value)))
    }

    return identifier.isEmpty ? UIDevice.current.model : identifier
  }
}
