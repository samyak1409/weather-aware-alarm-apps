import Flutter
import UIKit
import UserNotifications
import alarm

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    SwiftAlarmPlugin.registerBackgroundTasks()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAppIconChannel(engineBridge)
  }

  // Serves core's app_icon.dart (same handler in Nivaat's AppDelegate — keep
  // in sync). Icon ids "1"/"2"/"3": "1" = the primary AppIcon, "2"/"3" = the
  // AppIconTwo/AppIconThree alternate sets (declared via the
  // ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES build setting).
  private func registerAppIconChannel(_ engineBridge: FlutterImplicitEngineBridge) {
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CoreAppIcon")
    else { return }
    let names: [String: String?] = ["1": nil, "2": "AppIconTwo", "3": "AppIconThree"]
    FlutterMethodChannel(name: "core/app_icon", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        switch call.method {
        case "get":
          switch UIApplication.shared.alternateIconName {
          case "AppIconTwo": result("2")
          case "AppIconThree": result("3")
          default: result("1")
          }
        case "set":
          guard UIApplication.shared.supportsAlternateIcons,
                let args = call.arguments as? [String: Any],
                let id = args["id"] as? String,
                let name = names[id]
          else {
            result(false)
            return
          }
          UIApplication.shared.setAlternateIconName(name) { error in
            result(error == nil)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}
