import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let securityChannel = FlutterMethodChannel(
      name: "com.shis.securecalc/security",
      binaryMessenger: controller.binaryMessenger
    )

    securityChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "getSystemDeviceId":
        let persistentId = self.getOrCreatePersistentDeviceId()
        result(persistentId)

      case "setSecureFlag":
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func getOrCreatePersistentDeviceId() -> String {
    let service = "com.shis.securecalc.deviceid"
    let account = "persistent_device_id"

    // 1. Try to read persistent Device ID from iOS Keychain
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: kCFBooleanTrue!,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var dataTypeRef: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

    if status == errSecSuccess,
       let data = dataTypeRef as? Data,
       let persistentId = String(data: data, encoding: .utf8),
       !persistentId.isEmpty {
      return persistentId
    }

    // 2. Not found in Keychain: Generate hardware device ID
    let vendorId = UIDevice.current.identifierForVendor?.uuidString
      .replacingOccurrences(of: "-", with: "")
      .lowercased() ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let manufacturer = "apple"
    let model = self.getDeviceModel().lowercased().replacingOccurrences(of: " ", with: "")
    let newHardwareId = !vendorId.isEmpty ? "\(manufacturer)\(model)_\(vendorId)" : "\(manufacturer)\(model)"

    // 3. Persist generated ID into Keychain so it survives app uninstalls
    if let data = newHardwareId.data(using: .utf8) {
      let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
      ]
      SecItemAdd(addQuery as CFDictionary, nil)
    }

    return newHardwareId
  }

  private func getDeviceModel() -> String {
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

