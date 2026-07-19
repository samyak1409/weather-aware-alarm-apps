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

  // NivaatEngine.standard() also loads the selected alarm tone into
  // nivaatSelectedSound (shared with the background entrypoints).
  final engine = await NivaatEngine.standard();
  await engine.scheduler.ensureInitialized();

  if (Platform.isIOS) {
    await Workmanager().initialize(workmanagerDispatcher);
  }
  await engine.checks.initialize();

  final controller = NivaatController(engine: engine);
  unawaited(controller.init());
  // Notification permission, both platforms (skip cards; Android also the
  // ring card). The future resolves when the dialog is answered — kept so the
  // home screen's denied-banner can re-check at that exact moment.
  final permissionFlow =
      engine.notifier?.requestPermissionIfNeeded() ?? Future.value();
  unawaited(permissionFlow);
  // Android: ask once to skip battery optimisation, so off-charger Doze doesn't
  // throttle the background wind checks (no-op on iOS). If denied, the
  // BackgroundChecksBanner takes over from here (it stays hidden while this
  // flow's dialog is up, then re-checks).
  final batteryFlow = requestBatteryExemptionOnce();
  unawaited(batteryFlow);

  runApp(NivaatApp(
    controller: controller,
    permissionFlow: permissionFlow,
    batteryFlow: batteryFlow,
  ));
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
    return MaterialApp(
      title: 'Nivaat',
      debugShowCheckedModeBanner: false,
      theme: buildOledTheme(AppPalette.wind),
      home: RingGate(
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
