import Flutter
import UIKit
import UserNotifications
import alarm
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    SwiftAlarmPlugin.registerBackgroundTasks()
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.samyak.nivaat.refresh",
      frequency: NSNumber(value: 30 * 60)
    )
    // Overnight/idle trigger for the wind-check cascade; earliestBeginDate is
    // set per cascade rung from Dart (see IosCheckScheduler.scheduleCheck).
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "com.samyak.nivaat.processing"
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Dart's backgroundWorkDenied() asks "nivaat/battery" isExempt on iOS
    // too: the equivalent of Android's battery exemption here is Background
    // App Refresh — off means the wind-check BGTasks are never granted, so
    // the home screen shows the BackgroundChecksBanner.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NivaatBattery") {
      FlutterMethodChannel(name: "nivaat/battery", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          switch call.method {
          case "isExempt":
            result(UIApplication.shared.backgroundRefreshStatus == .available)
          default:
            result(FlutterMethodNotImplemented)
          }
        }
    }
    registerAppIconChannel(engineBridge)
  }

  // Serves core's app_icon.dart (same handler in Arunoday's AppDelegate —
  // keep in sync). Icon ids "1"/"2"/"3": "1" = the primary AppIcon, "2"/"3" =
  // the AppIconTwo/AppIconThree alternate sets (declared via the
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
