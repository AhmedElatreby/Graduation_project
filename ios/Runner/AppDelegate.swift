import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // UIScene lifecycle: engine-dependent setup happens here instead of
  // didFinishLaunchingWithOptions (see flutter.dev/to/uiscene-migration).
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GMSServices.provideAPIKey("AIzaSyARDxZgkunFLZCjoRYVbmQYPwYlv1NrMaw")
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
