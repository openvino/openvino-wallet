import UIKit
import Flutter
// import WalletSDK   // <- descomentá e importa tu SDK si ya lo tenés como xcframework/pod

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController

    // Canal que tu Dart usa: "WalletSDKPlugin"
    let channel = FlutterMethodChannel(
      name: "WalletSDKPlugin",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "initSDK":
        // TODO: invocá acá tu SDK nativo real
        // try? WalletSDK.shared.initialize()
        result(nil) // devolver nil = OK (sin error)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
