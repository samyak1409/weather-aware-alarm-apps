import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

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

  final engine = await NivaatEngine.standard();
  await engine.scheduler.ensureInitialized();

  if (Platform.isIOS) {
    await Workmanager().initialize(workmanagerDispatcher);
  }
  await engine.checks.initialize();

  final controller = NivaatController(engine: engine);
  unawaited(controller.init());
  // Android 13+ notification permission for skip cards (no-op elsewhere).
  unawaited(engine.notifier?.requestPermissionIfNeeded() ?? Future.value());

  runApp(NivaatApp(controller: controller));
}

class NivaatApp extends StatelessWidget {
  const NivaatApp({super.key, required this.controller});

  final NivaatController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nivaat',
      debugShowCheckedModeBanner: false,
      theme: buildOledTheme(AppPalette.wind),
      home: RingGate(
        appName: 'NIVAAT',
        child: HomeScreen(controller: controller),
      ),
    );
  }
}
