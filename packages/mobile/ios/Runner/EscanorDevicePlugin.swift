import AVFoundation
import Contacts
import Flutter
import UIKit

/// The iPhone side of the Escanor voice assistant: what iOS lets an app do for the person who asked. It is the counterpart of
/// EscanorDevicePlugin.kt on Android, answering the same calls on the "escanor/device" channel with the same shapes, and saying
/// plainly where iOS does not allow something (setting alarms, changing the volume, controlling other apps, listening for
/// "Hey Escanor" in the background) so the assistant can tell the person instead of failing silently.
public class EscanorDevicePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "escanor/device", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(EscanorDevicePlugin(), channel: channel)
  }

  private func result(_ ok: Bool, _ message: String? = nil) -> [String: Any] {
    var o: [String: Any] = ["ok": ok]
    if let message = message { o["message"] = message }
    return o
  }

  public func handle(_ call: FlutterMethodCall, result reply: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    // iOS does not let an app see what else is installed, so the assistant opens things by web address instead.
    case "listApps":
      reply(["apps": []])
    case "launchPackage":
      reply(result(false, "iOS does not let Escanor open other apps by name. I can open the website instead."))
    case "openUrl":
      guard let text = args["url"] as? String, let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
        return reply(result(false, "That is not a web address I can open."))
      }
      open(url, reply)

    // iOS always shows its own "Call" confirmation: an app cannot place a call silently.
    case "dial", "callNumber":
      tel(args["number"] as? String ?? "", reply)
    case "callContact":
      let wanted = (args["name"] as? String ?? "").lowercased()
      withContacts(reply) { contacts in
        guard let match = contacts.first(where: { $0.name.lowercased().contains(wanted) }), let number = match.numbers.first else {
          return reply(self.result(false, "I could not find \(wanted) in your contacts."))
        }
        self.tel(number, reply)
      }
    case "listContacts":
      withContacts(reply) { contacts in
        var out = self.result(true)
        out["contacts"] = contacts.map { ["name": $0.name, "numbers": $0.numbers] as [String: Any] }
        reply(out)
      }
    // Calls need no permission on iOS (the person confirms each one on screen).
    case "callStatus":
      reply(["granted": true])
    case "requestCallPermission":
      reply(result(true))

    // Controlling the phone: not something iOS allows.
    case "controlStatus":
      reply(["enabled": false, "available": false, "restricted": NSNull()])
    case "openControlSettings", "openAppInfo", "openSettings":
      // Every named screen opens Escanor's own page in the iPhone's Settings: iOS has no links to the others.
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return reply(result(false)) }
      open(url, reply)
    case "controlTurnOff":
      reply(result(true)) // never on: nothing to switch off
    case "control":
      reply(result(false, "iOS does not let an app press buttons or read other apps, so I cannot do that on an iPhone."))

    case "setAlarm":
      reply(result(false, "iOS does not let apps set alarms. Ask Siri, or open the Clock app."))
    case "setTimer":
      reply(result(false, "iOS does not let apps start timers. Ask Siri, or open the Clock app."))
    case "setTorch":
      setTorch(args["on"] as? Bool ?? true, reply)
    case "setVolume":
      reply(result(false, "iOS does not let apps change the volume. Use the buttons on the side of your iPhone."))

    // "Hey Escanor": iOS does not let an app listen in the background, so there is none here. The screen says so.
    case "wakeStatus":
      reply(["running": false, "modelReady": false, "downloading": false, "micAllowed": false, "supported": false])
    case "wakeListen", "wakePause":
      reply(nil)
    case "takeVoiceLink":
      reply(false)
    case "wakeDownloadModel", "wakeStart", "wakeStop", "wakeDeleteModel", "wakeOpenFullScreenSettings", "wakeTest":
      reply(result(false, "“Hey Escanor” works only on Android: iOS does not let an app listen in the background."))
    default:
      reply(FlutterMethodNotImplemented)
    }
  }

  private func open(_ url: URL, _ reply: @escaping FlutterResult) {
    DispatchQueue.main.async {
      UIApplication.shared.open(url, options: [:]) { ok in
        reply(self.result(ok, ok ? nil : "iOS would not open that."))
      }
    }
  }

  private func tel(_ number: String, _ reply: @escaping FlutterResult) {
    let digits = number.filter { $0.isNumber || $0 == "+" }
    guard digits.count >= 3, let url = URL(string: "tel://\(digits)") else {
      return reply(result(false, "That does not look like a phone number."))
    }
    open(url, reply)
  }

  private func withContacts(_ reply: @escaping FlutterResult, _ body: @escaping ([(name: String, numbers: [String])]) -> Void) {
    let store = CNContactStore()
    store.requestAccess(for: .contacts) { granted, _ in
      guard granted else {
        return DispatchQueue.main.async {
          reply(self.result(false, "Allow Escanor to read your contacts (iPhone Settings, Escanor, Contacts) so it can find who to call."))
        }
      }
      var rows: [(name: String, numbers: [String])] = []
      let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
      let request = CNContactFetchRequest(keysToFetch: keys)
      try? store.enumerateContacts(with: request) { c, _ in
        let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let numbers = c.phoneNumbers.map { $0.value.stringValue.filter { $0.isNumber || $0 == "+" } }.filter { $0.count >= 3 }
        if !name.isEmpty && !numbers.isEmpty && rows.count < 5000 { rows.append((name, numbers)) }
      }
      DispatchQueue.main.async { body(rows) }
    }
  }

  private func setTorch(_ on: Bool, _ reply: @escaping FlutterResult) {
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
      return reply(result(false, "This iPhone has no torch I can use."))
    }
    do {
      try device.lockForConfiguration()
      device.torchMode = on ? .on : .off
      device.unlockForConfiguration()
      reply(result(true))
    } catch {
      reply(result(false, "I could not switch the torch."))
    }
  }
}
