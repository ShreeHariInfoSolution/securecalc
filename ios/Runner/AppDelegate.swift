import Flutter
import UIKit

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
        let vendorId = UIDevice.current.identifierForVendor?.uuidString
          .replacingOccurrences(of: "-", with: "")
          .lowercased() ?? ""
        let manufacturer = "apple"
        let model = self.getDeviceModel().lowercased().replacingOccurrences(of: " ", with: "")
        let hardwareId = !vendorId.isEmpty ? "\(manufacturer)\(model)_\(vendorId)" : "\(manufacturer)\(model)"
        result(hardwareId)

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

