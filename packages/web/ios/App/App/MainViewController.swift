import Capacitor
import UIKit

/// The web view's controller, which also registers the Escanor assistant's phone tools (they live in this app, not in a package).
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(EscanorDevicePlugin())
    }
}
