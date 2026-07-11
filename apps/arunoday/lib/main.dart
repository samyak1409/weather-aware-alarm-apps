import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'src/bedtime_actions.dart';
import 'src/controller.dart';
import 'src/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler =
      AlarmPkgScheduler(soundAsset: 'assets/sounds/arunoday_dawn.wav');
  await scheduler.ensureInitialized();

  final controller = ArunodayController(
    store: ArunodayStore(),
    scheduler: scheduler,
  );
  unawaited(controller.init());

  runApp(ArunodayApp(controller: controller));
}

class ArunodayApp extends StatelessWidget {
  const ArunodayApp({super.key, required this.controller});

  final ArunodayController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arunoday',
      debugShowCheckedModeBanner: false,
      theme: buildOledTheme(AppPalette.dawn),
      home: RingGate(
        appName: 'ARUNODAY',
        actionsBuilder: (context, alarm) =>
            BedtimeActions.isBedtimeAlarm(alarm)
                ? BedtimeActions(controller: controller, ringingAlarm: alarm)
                : const SizedBox.shrink(),
        child: HomeScreen(controller: controller),
      ),
    );
  }
}
