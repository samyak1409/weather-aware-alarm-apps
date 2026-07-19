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
  }
}
