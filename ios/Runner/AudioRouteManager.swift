import Foundation
import AVFoundation
import UIKit
import Flutter
import WebRTC
import AVKit
import MediaPlayer

/// Single owner of iOS call audio routing following WhatsApp-style architecture.
/// - Keeps Bluetooth (.allowBluetooth and .allowBluetoothA2DP) always enabled in AVAudioSession
///   so all connected headphones (HFP/A2DP) are exposed to both the in-app call screen and iOS CallKit lock screen.
/// - Prioritizes connected headphones on call start and never drops to earpiece unless explicitly requested.
/// - Tracks the active Bluetooth device and reasserts it when WebRTC/CoreAudio voice processing causes a transient reset.
/// - Synchronizes seamlessly between the in-app call screen and iOS native lock-screen CallKit controls.
final class AudioRouteManager: NSObject, RTCAudioSessionDelegate {
  static let shared = AudioRouteManager()
  private override init() { super.init() }

  private enum Choice: Equatable {
    case auto
    case speaker
    case earpiece
    case bluetooth
  }

  private var channel: FlutterMethodChannel?
  private var observing = false

  private var choice: Choice = .auto
  private var userExplicitChoice: Choice? = nil
  private var pendingTarget: Choice? = nil
  private var isVideo = false
  private var active = false
  private var isApplying = false

  private var lastActiveHeadsetName: String?
  private var lastActiveHeadsetUid: String?
  private var lastKnownHeadsetConnected = false
  private var reassertWorkItems: [DispatchWorkItem] = []

  private var rtc: RTCAudioSession { RTCAudioSession.sharedInstance() }
  private var session: AVAudioSession { rtc.session }

  private let headsetInputTypes: [AVAudioSession.Port] = [
    .bluetoothHFP, .bluetoothLE, .headsetMic, .usbAudio, .carAudio
  ]
  private let headsetOutputTypes: [AVAudioSession.Port] = [
    .bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .headphones, .usbAudio, .carAudio, .airPlay
  ]

  private let baseCategoryOptions: AVAudioSession.CategoryOptions = [
    .allowBluetooth,
    .allowBluetoothA2DP,
    .allowAirPlay,
    .duckOthers
  ]

  // MARK: - Work Items Management

  private func cancelReassertions() {
    reassertWorkItems.forEach { $0.cancel() }
    reassertWorkItems.removeAll()
  }

  private func scheduleBluetoothReassertion() {
    cancelReassertions()

    // 1. Immediate apply attempt
    self.apply()

    // 2. Delayed attempts to re-acquire Bluetooth HFP as soon as CoreAudio/WebRTC finishes renegotiating
    let delays = [0.15, 0.35, 0.7, 1.2]
    for delay in delays {
      let item = DispatchWorkItem { [weak self] in
        guard let self = self, self.active, self.choice == .bluetooth else { return }
        let currentOut = self.session.currentRoute.outputs.first
        if let out = currentOut, self.headsetOutputTypes.contains(out.portType) {
          self.lastActiveHeadsetName = out.portName
          self.lastActiveHeadsetUid = out.uid
          self.emit()
          return
        }
        print("[AudioRoute] Reasserting bluetooth after \(delay)s delay (current output: \(currentOut?.portName ?? "none"))")
        self.apply()
        self.emit()
      }
      reassertWorkItems.append(item)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
  }

  // MARK: - Channel

  func attach(messenger: FlutterBinaryMessenger) {
    print("[AudioRoute] manager v14 (active headset tracking & reassertion) loaded")
    let ch = FlutterMethodChannel(name: "com.shis.securecalc/audio", binaryMessenger: messenger)
    channel = ch

    if !observing {
      rtc.add(self)
      let nc = NotificationCenter.default
      nc.addObserver(self, selector: #selector(routeChanged(_:)),
        name: AVAudioSession.routeChangeNotification, object: nil)
      nc.addObserver(self, selector: #selector(interrupted(_:)),
        name: AVAudioSession.interruptionNotification, object: nil)
      observing = true
    }

    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      let args = call.arguments as? [String: Any] ?? [:]

      switch call.method {
      case "configureCall":
        self.isVideo = (args["callType"] as? String) == "video"
        self.active = true
        self.userExplicitChoice = nil
        self.pendingTarget = nil
        self.cancelReassertions()

        // Capture initial headset if present in current outputs or available inputs
        if let out = self.session.currentRoute.outputs.first, self.headsetOutputTypes.contains(out.portType) {
          self.lastActiveHeadsetName = out.portName
          self.lastActiveHeadsetUid = out.uid
          self.lastKnownHeadsetConnected = true
        } else if let inp = self.externalInputs().first {
          self.lastActiveHeadsetName = inp.portName
          self.lastActiveHeadsetUid = inp.uid
          self.lastKnownHeadsetConnected = true
        } else {
          self.lastKnownHeadsetConnected = self.hasConnectedHeadset()
        }

        // If headphones are connected, start directly on bluetooth so it never drops to earpiece
        self.choice = self.lastKnownHeadsetConnected ? .bluetooth : (self.isVideo ? .speaker : .earpiece)
        self.apply()
        if self.choice == .bluetooth {
          self.scheduleBluetoothReassertion()
        }
        result(self.state())

      case "setAudioRoute":
        let routeStr = args["route"] as? String ?? ""
        let portUid = args["portUid"] as? String ?? ""
        let name = args["name"] as? String ?? ""
        print("[AudioRoute] setAudioRoute requested: route=\(routeStr), name=\(name), portUid=\(portUid)")

        self.cancelReassertions()
        let newChoice: Choice
        switch routeStr {
        case "speaker":
          newChoice = .speaker
          self.userExplicitChoice = .speaker
        case "earpiece":
          newChoice = .earpiece
          self.userExplicitChoice = .earpiece
        case "bluetooth":
          newChoice = .bluetooth
          self.userExplicitChoice = .bluetooth
          if !name.isEmpty { self.lastActiveHeadsetName = name }
          if !portUid.isEmpty { self.lastActiveHeadsetUid = portUid }
          self.lastKnownHeadsetConnected = true
        default:
          newChoice = self.isVideo ? .speaker : (self.hasConnectedHeadset() ? .bluetooth : .earpiece)
        }

        self.pendingTarget = newChoice
        self.choice = newChoice
        self.apply()
        if newChoice == .bluetooth {
          self.scheduleBluetoothReassertion()
        }

        // Schedule confirmation emissions to ensure Flutter is in sync with hardware
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
          self?.emit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
          self?.pendingTarget = nil
          self?.emit()
        }

        result(self.state())

      case "ensureAudioEnabled":
        if !self.rtc.isAudioEnabled {
          self.rtc.isAudioEnabled = true
        }
        result(true)

      case "setCallType":
        let video = (args["isVideo"] as? Bool) ?? ((args["callType"] as? String) == "video")
        let upgraded = video && !self.isVideo
        self.isVideo = video
        if upgraded && self.choice == .earpiece && self.userExplicitChoice == nil {
          self.choice = self.hasConnectedHeadset() ? .bluetooth : .speaker
        }
        self.apply()
        result(self.state())

      case "reapplyRoute":
        print("[AudioRoute] reapplyRoute called, keeping active choice=\(self.choice)")
        if self.choice == .bluetooth || (self.lastKnownHeadsetConnected && self.userExplicitChoice == nil) {
          self.choice = .bluetooth
          self.scheduleBluetoothReassertion()
        } else {
          self.apply()
        }
        result(self.state())

      case "getAudioRouteInfo":
        result(self.state())

      case "showRoutePicker":
        self.showSystemRoutePicker()
        result(true)

      case "endCall":
        self.active = false
        self.choice = .auto
        self.userExplicitChoice = nil
        self.pendingTarget = nil
        self.isVideo = false
        self.lastKnownHeadsetConnected = false
        self.lastActiveHeadsetName = nil
        self.lastActiveHeadsetUid = nil
        self.cancelReassertions()
        self.rtc.lockForConfiguration()
        try? self.rtc.overrideOutputAudioPort(.none)
        try? self.session.overrideOutputAudioPort(.none)
        try? self.session.setPreferredInput(nil)
        self.rtc.unlockForConfiguration()
        UIDevice.current.isProximityMonitoringEnabled = false
        result(self.state())

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Apply

  private func apply() {
    guard active, !isApplying else { return }
    isApplying = true
    defer { isApplying = false }

    let mode: AVAudioSession.Mode = isVideo ? .videoChat : .voiceChat
    let options: AVAudioSession.CategoryOptions = (choice == .speaker)
      ? baseCategoryOptions.union(.defaultToSpeaker)
      : baseCategoryOptions

    print("[AudioRoute] Applying route: \(choice), isVideo: \(isVideo), options: \(options.rawValue)")

    rtc.lockForConfiguration()
    defer { rtc.unlockForConfiguration() }

    do {
      let config = RTCAudioSessionConfiguration.webRTC()
      config.category = AVAudioSession.Category.playAndRecord.rawValue
      config.mode = mode.rawValue
      config.categoryOptions = options
      try? rtc.setConfiguration(config)

      try session.setCategory(.playAndRecord, mode: mode, options: options)
      try session.setActive(true)

      switch choice {
      case .auto:
        if hasConnectedHeadset() {
          try? rtc.overrideOutputAudioPort(.none)
          try? session.overrideOutputAudioPort(.none)
          if let target = targetHeadsetInput() {
            try? session.setPreferredInput(target)
            try? rtc.setPreferredInput(target)
            print("[AudioRoute] .auto routed to Headset preferredInput=\(target.portName)")
          } else {
            try? session.setPreferredInput(nil)
            print("[AudioRoute] .auto routed to Headset (default route)")
          }
        } else if isVideo {
          try? session.setPreferredInput(nil)
          try? rtc.overrideOutputAudioPort(.speaker)
          try? session.overrideOutputAudioPort(.speaker)
          print("[AudioRoute] .auto routed to Speaker (video)")
        } else {
          try? rtc.overrideOutputAudioPort(.none)
          try? session.overrideOutputAudioPort(.none)
          try? session.setPreferredInput(nil)
          print("[AudioRoute] .auto routed to Earpiece (voice)")
        }

      case .bluetooth:
        try? rtc.overrideOutputAudioPort(.none)
        try? session.overrideOutputAudioPort(.none)
        if let target = targetHeadsetInput() {
          try? session.setPreferredInput(target)
          try? rtc.setPreferredInput(target)
          print("[AudioRoute] Routed to Bluetooth/Headset preferredInput=\(target.portName)")
        } else {
          try? session.setPreferredInput(nil)
          print("[AudioRoute] Routed to Bluetooth/Headset (preferredInput=nil, awaiting port)")
        }

      case .speaker:
        try? session.setPreferredInput(nil)
        try? rtc.overrideOutputAudioPort(.speaker)
        try? session.overrideOutputAudioPort(.speaker)
        print("[AudioRoute] Forced to built-in Speaker")

      case .earpiece:
        try? rtc.overrideOutputAudioPort(.none)
        try? session.overrideOutputAudioPort(.none)
        if hasConnectedHeadset(), let mic = builtInMic() {
          try? session.setPreferredInput(mic)
          try? rtc.setPreferredInput(mic)
          print("[AudioRoute] Forced to Phone Earpiece by setting preferredInput to builtInMic")
        } else {
          try? session.setPreferredInput(nil)
          print("[AudioRoute] Forced to Phone Earpiece (Receiver)")
        }
      }

      if !rtc.isAudioEnabled {
        rtc.isAudioEnabled = true
      }
    } catch {
      print("[AudioRoute] Error applying route: \(error)")
    }
  }

  // MARK: - System Route Picker

  func showSystemRoutePicker() {
    DispatchQueue.main.async {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        ?? UIApplication.shared.windows.first { $0.isKeyWindow }
        ?? UIApplication.shared.windows.first
      guard let rootVC = window?.rootViewController else {
        print("[AudioRoute] showSystemRoutePicker failed: no rootVC found")
        return
      }

      var topVC = rootVC
      while let presented = topVC.presentedViewController, !presented.isBeingDismissed {
        topVC = presented
      }

      func findButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        for sub in view.subviews {
          if let found = findButton(in: sub) { return found }
        }
        return nil
      }

      let picker = AVRoutePickerView(frame: CGRect(
        x: max(0, topVC.view.bounds.midX - 22),
        y: max(0, topVC.view.bounds.midY - 22),
        width: 44,
        height: 44
      ))
      picker.prioritizesVideoDevices = false
      picker.alpha = 0.01
      topVC.view.addSubview(picker)
      picker.layoutIfNeeded()

      func trigger() {
        if let button = findButton(in: picker) {
          button.sendActions(for: .touchUpInside)
          print("[AudioRoute] Triggered AVRoutePickerView successfully")
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            picker.removeFromSuperview()
          }
        } else {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let button = findButton(in: picker) {
              button.sendActions(for: .touchUpInside)
              print("[AudioRoute] Triggered AVRoutePickerView (delayed) successfully")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
              picker.removeFromSuperview()
            }
          }
        }
      }
      trigger()
    }
  }

  /// Call from CallKit didActivateAudioSession.
  func reapply() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.active else { return }
      if self.choice == .bluetooth || (self.lastKnownHeadsetConnected && self.userExplicitChoice == nil) {
        self.choice = .bluetooth
        self.scheduleBluetoothReassertion()
      } else {
        self.apply()
      }
      self.emit()
    }
  }

  // MARK: - RTCAudioSessionDelegate

  func audioSessionDidStartPlayOrRecord(_ session: RTCAudioSession) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.active else { return }
      print("[AudioRoute] WebRTC started play/record, current choice: \(self.choice)")
      if self.choice == .bluetooth || (self.lastKnownHeadsetConnected && self.userExplicitChoice == nil) {
        self.choice = .bluetooth
        self.scheduleBluetoothReassertion()
      } else {
        self.apply()
      }
      self.emit()
    }
  }

  // MARK: - Ports

  private func externalInputs() -> [AVAudioSessionPortDescription] {
    (session.availableInputs ?? []).filter { headsetInputTypes.contains($0.portType) }
  }

  private func builtInMic() -> AVAudioSessionPortDescription? {
    session.availableInputs?.first { $0.portType == .builtInMic }
  }

  private func targetHeadsetInput() -> AVAudioSessionPortDescription? {
    let inputs = externalInputs()
    if inputs.isEmpty { return nil }

    // 1. Match by tracked active headset name
    if let name = lastActiveHeadsetName, !name.isEmpty,
       let match = inputs.first(where: { $0.portName == name }) {
      return match
    }

    // 2. Match by tracked active headset UID
    if let uid = lastActiveHeadsetUid, !uid.isEmpty,
       let match = inputs.first(where: { $0.uid == uid }) {
      return match
    }

    // 3. Fall back to the first available external headset input
    return inputs.first
  }

  private func hasHeadsetOutput(_ r: AVAudioSessionRouteDescription) -> Bool {
    r.outputs.contains { headsetOutputTypes.contains($0.portType) }
  }

  private func hasConnectedHeadset() -> Bool {
    if lastKnownHeadsetConnected { return true }
    if !externalInputs().isEmpty { return true }
    if let avail = session.availableInputs, avail.contains(where: { headsetInputTypes.contains($0.portType) }) {
      return true
    }
    if session.currentRoute.outputs.contains(where: { headsetOutputTypes.contains($0.portType) }) {
      return true
    }
    return false
  }

  private func activeHeadsetName() -> String {
    if let out = session.currentRoute.outputs.first, headsetOutputTypes.contains(out.portType) {
      return out.portName
    }
    if let name = lastActiveHeadsetName, !name.isEmpty {
      return name
    }
    if let inp = externalInputs().first {
      return inp.portName
    }
    for out in session.currentRoute.outputs {
      if headsetOutputTypes.contains(out.portType) {
        return out.portName
      }
    }
    return "Headphones"
  }

  // MARK: - Notifications

  @objc private func interrupted(_ n: Notification) {
    guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.active else { return }
      self.apply()
      self.emit()
    }
  }

  @objc private func routeChanged(_ n: Notification) {
    DispatchQueue.main.async { [weak self] in self?.handleRouteChange(n) }
  }

  private func handleRouteChange(_ n: Notification) {
    guard active, !isApplying else { return }
    let raw = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
    let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
    print("[AudioRoute] Route changed: reason=\(raw) (\(String(describing: reason)))")

    let outPort = session.currentRoute.outputs.first
    print("[AudioRoute] Current output now: \(outPort?.portName ?? "none") (\(outPort?.portType.rawValue ?? ""))")

    switch reason {
    case .newDeviceAvailable:
      choice = .bluetooth
      userExplicitChoice = nil
      pendingTarget = nil
      lastKnownHeadsetConnected = true
      if let out = outPort, headsetOutputTypes.contains(out.portType) {
        lastActiveHeadsetName = out.portName
        lastActiveHeadsetUid = out.uid
      }
      scheduleBluetoothReassertion()
      emit()

    case .oldDeviceUnavailable:
      userExplicitChoice = nil
      pendingTarget = nil
      cancelReassertions()
      let stillHasHeadset = (session.availableInputs ?? []).contains { headsetInputTypes.contains($0.portType) }
        || session.currentRoute.outputs.contains { headsetOutputTypes.contains($0.portType) }
      if !stillHasHeadset {
        lastKnownHeadsetConnected = false
        lastActiveHeadsetName = nil
        lastActiveHeadsetUid = nil
        choice = isVideo ? .speaker : .earpiece
      } else {
        lastKnownHeadsetConnected = true
        choice = .bluetooth
        if let out = session.currentRoute.outputs.first, headsetOutputTypes.contains(out.portType) {
          lastActiveHeadsetName = out.portName
          lastActiveHeadsetUid = out.uid
        }
        scheduleBluetoothReassertion()
      }
      apply()
      emit()

    case .categoryChange, .override, .routeConfigurationChange:
      if let target = pendingTarget {
        if matchesTarget(outPort: outPort, target: target) {
          pendingTarget = nil
        }
      } else {
        if let out = outPort {
          if out.portType == .builtInSpeaker {
            if userExplicitChoice == .speaker {
              choice = .speaker
            } else if lastKnownHeadsetConnected || hasConnectedHeadset() {
              print("[AudioRoute] Transient speaker route detected with connected headset. Preserving Bluetooth!")
              choice = .bluetooth
              scheduleBluetoothReassertion()
            } else {
              choice = .speaker
            }
          } else if headsetOutputTypes.contains(out.portType) {
            choice = .bluetooth
            lastActiveHeadsetName = out.portName
            lastActiveHeadsetUid = out.uid
            lastKnownHeadsetConnected = true
          } else if out.portType == .builtInReceiver {
            // NEVER automatically lock to earpiece unless user deliberately selected earpiece!
            if userExplicitChoice == .earpiece {
              choice = .earpiece
            } else if lastKnownHeadsetConnected || hasConnectedHeadset() {
              // During WebRTC startup / voice processing enable, iOS temporarily resets to Receiver.
              // Preserve Bluetooth and reassert Bluetooth HFP immediately.
              print("[AudioRoute] Transient receiver route detected during category/config change. Reasserting Bluetooth!")
              choice = .bluetooth
              scheduleBluetoothReassertion()
            } else if !isVideo {
              choice = .earpiece
            }
          }
        }
      }
      emit()

    default:
      emit()
    }
  }

  private func matchesTarget(outPort: AVAudioSessionPortDescription?, target: Choice) -> Bool {
    guard let out = outPort else { return false }
    switch target {
    case .speaker:
      return out.portType == .builtInSpeaker
    case .earpiece:
      return out.portType == .builtInReceiver
    case .bluetooth:
      return headsetOutputTypes.contains(out.portType)
    case .auto:
      return true
    }
  }

  // MARK: - State

  private func actualRoute() -> String {
    if let target = pendingTarget {
      switch target {
      case .speaker: return "speaker"
      case .earpiece: return "earpiece"
      case .bluetooth: return "bluetooth"
      case .auto:
        if lastKnownHeadsetConnected || hasConnectedHeadset() { return "bluetooth" }
        return isVideo ? "speaker" : "earpiece"
      }
    }

    guard let t = session.currentRoute.outputs.first?.portType else {
      if lastKnownHeadsetConnected || hasConnectedHeadset() { return "bluetooth" }
      return isVideo ? "speaker" : "earpiece"
    }
    if t == .builtInSpeaker { return "speaker" }
    if t == .builtInReceiver {
      if choice == .bluetooth && (lastKnownHeadsetConnected || hasConnectedHeadset()) {
        return "bluetooth"
      }
      return "earpiece"
    }
    if headsetOutputTypes.contains(t) { return "bluetooth" }
    return isVideo ? "speaker" : "earpiece"
  }

  private func state() -> [String: Any] {
    let r = session.currentRoute
    let inPort = r.inputs.first
    let outPort = r.outputs.first
    let actRoute = actualRoute()
    let hasHead = lastKnownHeadsetConnected || hasConnectedHeadset()

    var activeUid: String
    var activeName: String
    var activeType: String

    if actRoute == "speaker" {
      activeUid = "speaker"
      activeName = "Speaker"
      activeType = AVAudioSession.Port.builtInSpeaker.rawValue
    } else if actRoute == "earpiece" {
      activeUid = "earpiece"
      activeName = "Phone Earpiece"
      activeType = AVAudioSession.Port.builtInReceiver.rawValue
    } else {
      let name = activeHeadsetName()
      activeUid = "bluetooth"
      activeName = name
      activeType = outPort?.portType.rawValue ?? "BluetoothHFP"
    }

    var inputs: [[String: Any]] = []
    let extInps = externalInputs()
    if !extInps.isEmpty {
      for inp in extInps {
        let isCar = inp.portName.lowercased().contains("car") || inp.portType == .carAudio
        let isSelected = (actRoute == "bluetooth") &&
          (outPort?.portName == inp.portName || inPort?.portName == inp.portName || lastActiveHeadsetName == inp.portName || lastActiveHeadsetUid == inp.uid)
        inputs.append([
          "uid": inp.uid,
          "name": inp.portName,
          "type": inp.portType.rawValue,
          "isCar": isCar,
          "selected": isSelected
        ])
      }
    } else if hasHead {
      let name = activeHeadsetName()
      let isCar = name.lowercased().contains("car")
      inputs.append([
        "uid": "bluetooth",
        "name": name,
        "type": activeType,
        "isCar": isCar,
        "selected": actRoute == "bluetooth"
      ])
    }

    return [
      "success": true,
      "actualInputPort": inPort?.portName ?? "Unknown",
      "actualOutputPort": outPort?.portName ?? "Unknown",
      "actualInputType": inPort?.portType.rawValue ?? "",
      "actualOutputType": outPort?.portType.rawValue ?? "",
      "actualRoute": actRoute,
      "activeDeviceUid": activeUid,
      "activeDeviceName": activeName,
      "activeDeviceType": activeType,
      "hasBluetooth": hasHead,
      "headsetName": (actRoute == "bluetooth" || hasHead) ? activeName : "",
      "inputs": inputs
    ]
  }

  private func updateProximity() {
    let want = active && !isVideo && (choice == .earpiece)
    if UIDevice.current.isProximityMonitoringEnabled != want {
      UIDevice.current.isProximityMonitoringEnabled = want
    }
  }

  private func emit() {
    updateProximity()
    channel?.invokeMethod("onAudioRouteChanged", arguments: state())
  }
}
