import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'src/bedtime_actions.dart';
import 'src/controller.dart';
import 'src/home_screen.dart';
import 'src/notifications.dart';
import 'src/sound_selection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  applyMotionPacing();
  await lockToPortrait();
  await Appearance.load();
  // One scheduler for BOTH wake and bedtime. On Android → the alarm package
  // (its ring screen still hosts the bedtime +1h ritual). On iOS 26+ →
  // AlarmKit: a real system alarm that survives force-quit and reboot, so a
  // bedtime nudge can never silently fail to fire. The iOS trade-off is the
  // in-app ritual button (AlarmKit alerts are Stop-only) — reliability wins.
  // Screenshot harness builds skip real schedulers so AlarmKit / notification
  // permission dialogs never cover the UI being captured.
  final scheduler = kScreenshotHarness
      ? const NoOpAlarmScheduler()
      : await createAlarmScheduler(
          soundAssetForVolume: arunodaySoundForVolume,
          tintColor: '#FFB067',
        );
  try {
    await scheduler.ensureInitialized();
  } on Exception catch (e) {
    // Never brick launch on a plugin hiccup — same policy as Nivaat.
    debugPrint('arunoday Alarm.init failed (non-fatal): $e');
  }

  final controller = ArunodayController(
    store: ArunodayStore(),
    scheduler: scheduler,
  );
  unawaited(controller.init());
  // Notification permission (Android: the ring's card/full-screen UI). The
  // future resolves when the dialog is answered — kept so the home screen's
  // denied-banner can re-check at that exact moment. Skip in harness builds.
  final permissionFlow = kScreenshotHarness
      ? Future<void>.value()
      : requestNotificationPermission();
  unawaited(permissionFlow);

  runApp(ArunodayApp(controller: controller, permissionFlow: permissionFlow));
}

class ArunodayApp extends StatelessWidget {
  const ArunodayApp({
    super.key,
    required this.controller,
    required this.permissionFlow,
  });

  final ArunodayController controller;
  final Future<void> permissionFlow;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Appearance.heavyType,
      builder: (_, heavy, child) => MaterialApp(
        title: 'Arunoday',
        debugShowCheckedModeBanner: false,
        theme: buildOledTheme(AppPalette.dawn, heavyType: heavy),
        home: child,
      ),
      child: RingGate(
        appName: 'ARUNODAY',
        // Stopping (or starting) a ring re-arms the next wake/bedtime right
        // away instead of waiting for the next app open.
        onRingingChanged: () => unawaited(controller.resync()),
        actionsBuilder: (context, alarm) =>
            BedtimeActions.isBedtimeAlarm(alarm)
                ? BedtimeActions(controller: controller, ringingAlarm: alarm)
                : const SizedBox.shrink(),
        child: HomeScreen(
          controller: controller,
          permissionFlow: permissionFlow,
        ),
      ),
    );
  }
}
