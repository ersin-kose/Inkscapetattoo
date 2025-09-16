import Flutter
import UIKit
#if canImport(StoreKitTest)
import StoreKitTest
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // StoreKit Test yapılandırmasını simülatörde ve DEBUG derlemede başlat.
    #if DEBUG
    if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
      #if canImport(StoreKitTest)
      if let url = Bundle.main.url(forResource: "Configuration", withExtension: "storekit", subdirectory: "StoreKit") {
        if #available(iOS 14.0, *) {
          do {
            let session = try SKTestSession(configurationFileURL: url)
            session.resetToDefaultState()
            session.disableDialogs = false
            session.askToBuyEnabled = false
            session.start()
            NSLog("[StoreKitTest] Session started with %@", url.absoluteString)
          } catch {
            NSLog("[StoreKitTest] Failed to start: %@", error.localizedDescription)
          }
        }
      } else {
        NSLog("[StoreKitTest] Configuration.storekit not found in bundle")
      }
      #endif
    }
    #endif
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
