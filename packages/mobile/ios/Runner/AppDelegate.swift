import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The phone side of the voice assistant ("escanor/device"): calls, contacts, links, torch, and what iOS does not allow.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EscanorDevicePlugin") {
      EscanorDevicePlugin.register(with: registrar)
    }
  }
}
