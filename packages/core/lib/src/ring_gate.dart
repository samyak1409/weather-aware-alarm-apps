import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Wraps the app and overlays a full-screen stop UI whenever an alarm from
/// the `alarm` package is ringing (i.e. the app is open during ring).
class RingGate extends StatelessWidget {
  const RingGate({super.key, required this.appName, required this.child});

  final String appName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AlarmSet>(
      stream: Alarm.ringing,
      builder: (context, snapshot) {
        final ringing = snapshot.data?.alarms ?? const <AlarmSettings>{};
        if (ringing.isEmpty) return child;
        return _RingScreen(appName: appName, alarms: ringing.toList());
      },
    );
  }
}

class _RingScreen extends StatelessWidget {
  const _RingScreen({required this.appName, required this.alarms});

  final String appName;
  final List<AlarmSettings> alarms;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = TimeOfDay.now();
    final first = alarms.first;
    return Scaffold(
      backgroundColor: AppPalette.trueBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              Text(appName, style: text.labelSmall),
              const Spacer(),
              Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                style: text.displayLarge,
              ),
              const SizedBox(height: 12),
              Text(
                first.notificationSettings.body,
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  onPressed: () async {
                    for (final a in alarms) {
                      await Alarm.stop(a.id);
                    }
                  },
                  child: const Text('STOP', style: TextStyle(letterSpacing: 2)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
