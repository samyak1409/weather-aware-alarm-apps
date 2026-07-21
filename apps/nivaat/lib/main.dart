import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'src/battery_optimization.dart';
import 'src/controller.dart';
import 'src/engine.dart';
import 'src/home_screen.dart';

/// iOS BGAppRefresh dispatcher (Workmanager). Runs in a background isolate.
@pragma('vm:entry-point')
void workmanagerDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    await (await NivaatEngine.standard()).evaluateAll();
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  applyMotionPacing();
  await Appearance.load();

  // NivaatEngine.standard() also loads the selected alarm tone into
  // nivaatSelectedSound (shared with the background entrypoints).
  final engine = await NivaatEngine.standard();
  try {
    await engine.scheduler.ensureInitialized();
  } on Exception catch (e) {
    // Never brick launch on a plugin hiccup — same policy as CheckScheduler.
    // Errors (asserts / type bugs) still propagate.
    debugPrint('nivaat Alarm.init failed (non-fatal): $e');
  }

  if (Platform.isIOS) {
    await Workmanager().initialize(workmanagerDispatcher);
  }

  final controller = NivaatController(engine: engine);
  // Notification permission, both platforms (skip cards; Android also the
  // ring card). The future resolves when the dialog is answered — kept so the
  // home screen's denied-banner can re-check at that exact moment.
  // Screenshot harness: skip the system notif prompt so it never covers UI.
  final permissionFlow = kScreenshotHarness
      ? Future<void>.value()
      : (engine.notifier?.requestPermissionIfNeeded() ?? Future.value());
  unawaited(permissionFlow);
  // Android: ask once to skip battery optimisation — skip in harness too.
  final batteryFlow = kScreenshotHarness
      ? Future<void>.value()
      : requestBatteryExemptionOnce();
  unawaited(batteryFlow);

  runApp(NivaatApp(
    controller: controller,
    permissionFlow: permissionFlow,
    batteryFlow: batteryFlow,
  ));

  // checks.initialize() must run on BOTH platforms — on iOS it seeds the
  // periodic BGAppRefresh chain (the Dart-side submit; the AppDelegate only
  // registers the task handler). On Android, AndroidAlarmManager.initialize()
  // spins up a second FlutterEngine for its background isolate; doing that
  // while the main engine is still cold-starting raced release builds on real
  // devices (launch animation, then immediate death — ~1/10 with the system
  // dialog, rest silent), so it's deferred until the first frame is up.
  // Cascade booking in controller.init() follows right after either way.
  if (Platform.isAndroid) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_finishStartup(engine, controller));
    });
  } else {
    unawaited(_finishStartup(engine, controller));
  }
}

Future<void> _finishStartup(
  NivaatEngine engine,
  NivaatController controller,
) async {
  try {
    await engine.checks.initialize();
  } on Exception catch (e) {
    debugPrint('nivaat CheckScheduler.initialize failed (non-fatal): $e');
  }
  await controller.init();
}

class NivaatApp extends StatelessWidget {
  const NivaatApp({
    super.key,
    required this.controller,
    required this.permissionFlow,
    required this.batteryFlow,
  });

  final NivaatController controller;
  final Future<void> permissionFlow;
  final Future<void> batteryFlow;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Appearance.heavyType,
      builder: (_, heavy, child) => MaterialApp(
        title: 'Nivaat',
        debugShowCheckedModeBanner: false,
        theme: buildOledTheme(AppPalette.wind, heavyType: heavy),
        home: child,
      ),
      child: RingGate(
        appName: 'NIVAAT',
        // A ring starting or being stopped resyncs immediately, so the rang
        // row is in history while the alarm still sounds (Rule 1 logs it).
        onRingingChanged: () => unawaited(controller.resync()),
        child: HomeScreen(
          controller: controller,
          permissionFlow: permissionFlow,
          batteryFlow: batteryFlow,
        ),
      ),
    );
  }
}
