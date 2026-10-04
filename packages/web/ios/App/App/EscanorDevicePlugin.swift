import Capacitor
import Contacts
import AVFoundation
import UIKit

/// The iPhone side of the Escanor voice assistant: what iOS lets an app do for the person who asked. It is the counterpart of
/// EscanorDevicePlugin.java on Android, answering the same calls with the same shapes, and saying plainly where iOS does not allow
/// something (setting alarms, changing the volume, controlling other apps, listening for "Hey Escanor" in the background) so the
/// assistant can tell the person instead of failing silently.
@objc(EscanorDevicePlugin)
public class EscanorDevicePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "EscanorDevicePlugin"
    public let jsName = "EscanorDevice"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "listApps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "launchPackage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openUrl", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "dial", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "callNumber", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "callContact", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listContacts", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "callStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestCallPermission", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "controlStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openControlSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openAppInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "control", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setAlarm", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTimer", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTorch", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setVolume", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "wakeStatus", returnType: CAPPluginReturnPromise),
    ]

    private func result(_ ok: Bool, _ message: String? = nil) -> JSObject {
        var o: JSObject = ["ok": ok]
        if let message = message { o["message"] = message }
        return o
    }

    // MARK: - apps and links

    /// iOS does not let an app see what else is installed, so the assistant opens things by web address instead.
    @objc func listApps(_ call: CAPPluginCall) {
        call.resolve(["apps": []])
    }

    @objc func launchPackage(_ call: CAPPluginCall) {
        call.resolve(result(false, "iOS does not let Escanor open other apps by name. I can open the website instead."))
    }

    @objc func openUrl(_ call: CAPPluginCall) {
        guard let text = call.getString("url"), let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            call.resolve(result(false, "That is not a web address I can open."))
            return
        }
        open(url, call)
    }

    private func open(_ url: URL, _ call: CAPPluginCall) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { ok in
                call.resolve(self.result(ok, ok ? nil : "iOS would not open that."))
            }
        }
    }

    // MARK: - calls and contacts

    /// iOS always shows its own "Call" confirmation: an app cannot place a call silently.
    private func tel(_ number: String, _ call: CAPPluginCall) {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3, let url = URL(string: "tel://\(digits)") else {
            call.resolve(result(false, "That does not look like a phone number."))
            return
        }
        open(url, call)
    }

    @objc func dial(_ call: CAPPluginCall) { tel(call.getString("number") ?? "", call) }

    @objc func callNumber(_ call: CAPPluginCall) { tel(call.getString("number") ?? "", call) }

    @objc func callContact(_ call: CAPPluginCall) {
        let wanted = (call.getString("name") ?? "").lowercased()
        withContacts(call) { contacts in
            guard let match = contacts.first(where: { $0.name.lowercased().contains(wanted) }), let number = match.numbers.first else {
                call.resolve(self.result(false, "I could not find \(wanted) in your contacts."))
                return
            }
            self.tel(number, call)
        }
    }

    @objc func listContacts(_ call: CAPPluginCall) {
        withContacts(call) { contacts in
            var out: JSObject = self.result(true)
            out["contacts"] = contacts.map { ["name": $0.name, "numbers": $0.numbers] as JSObject }
            call.resolve(out)
        }
    }

    private func withContacts(_ call: CAPPluginCall, _ body: @escaping ([(name: String, numbers: [String])]) -> Void) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                call.resolve(self.result(false, "Allow Escanor to read your contacts (iPhone Settings, Escanor, Contacts) so it can find who to call."))
                return
            }
            var rows: [(name: String, numbers: [String])] = []
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: request) { c, _ in
                let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let numbers = c.phoneNumbers.map { $0.value.stringValue.filter { $0.isNumber || $0 == "+" } }.filter { $0.count >= 3 }
                if !name.isEmpty && !numbers.isEmpty && rows.count < 5000 { rows.append((name, numbers)) }
            }
            body(rows)
        }
    }

    /// Calls need no permission on iOS (the person confirms each one on screen).
    @objc func callStatus(_ call: CAPPluginCall) { call.resolve(["granted": true]) }

    @objc func requestCallPermission(_ call: CAPPluginCall) { call.resolve(result(true)) }

    // MARK: - controlling the phone: not something iOS allows

    @objc func controlStatus(_ call: CAPPluginCall) {
        call.resolve(["enabled": false, "available": false, "restricted": NSNull()])
    }

    @objc func openControlSettings(_ call: CAPPluginCall) { openAppInfo(call) }

    @objc func control(_ call: CAPPluginCall) {
        call.resolve(result(false, "iOS does not let an app press buttons or read other apps, so I cannot do that on an iPhone."))
    }

    // MARK: - alarms, torch, volume, settings

    @objc func setAlarm(_ call: CAPPluginCall) {
        call.resolve(result(false, "iOS does not let apps set alarms. Ask Siri, or open the Clock app."))
    }

    @objc func setTimer(_ call: CAPPluginCall) {
        call.resolve(result(false, "iOS does not let apps start timers. Ask Siri, or open the Clock app."))
    }

    @objc func setTorch(_ call: CAPPluginCall) {
        let on = call.getBool("on") ?? true
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            call.resolve(result(false, "This iPhone has no torch I can use."))
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            call.resolve(result(true))
        } catch {
            call.resolve(result(false, "I could not switch the torch."))
        }
    }

    @objc func setVolume(_ call: CAPPluginCall) {
        call.resolve(result(false, "iOS does not let apps change the volume. Use the buttons on the side of your iPhone."))
    }

    @objc func openAppInfo(_ call: CAPPluginCall) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return call.resolve(result(false)) }
        open(url, call)
    }

    /// Every named screen opens Escanor's own page in the iPhone's Settings: iOS has no links to the others.
    @objc func openSettings(_ call: CAPPluginCall) { openAppInfo(call) }

    // MARK: - "Hey Escanor"

    /// iOS does not let an app listen in the background, so there is no "Hey Escanor" here. The screen says so.
    @objc func wakeStatus(_ call: CAPPluginCall) {
        call.resolve(["running": false, "modelReady": false, "downloading": false, "micAllowed": false, "supported": false])
    }
}
