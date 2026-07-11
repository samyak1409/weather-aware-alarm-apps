import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Wraps the app and overlays a full-screen stop UI whenever an alarm from
/// the `alarm` package is ringing (i.e. the app is open during ring).
///
/// [actionsBuilder] lets an app add per-alarm actions above the STOP button
/// (e.g. Arunoday's bedtime ritual: delay bedtime, adjust tomorrow's wake).
class RingGate extends StatelessWidget {
  const RingGate({
    super.key,
    required this.appName,
    required this.child,
    this.actionsBuilder,
  });

  final String appName;
  final Widget child;
  final Widget Function(BuildContext context, AlarmSettings alarm)?
      actionsBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AlarmSet>(
      stream: Alarm.ringing,
      builder: (context, snapshot) {
        final ringing = snapshot.data?.alarms ?? const <AlarmSettings>{};
        if (ringing.isEmpty) return child;
        return _RingScreen(
          appName: appName,
          alarms: ringing.toList(),
          actionsBuilder: actionsBuilder,
        );
      },
    );
  }
}

class _RingScreen extends StatelessWidget {
  const _RingScreen({
    required this.appName,
    required this.alarms,
    this.actionsBuilder,
  });

  final String appName;
  final List<AlarmSettings> alarms;
  final Widget Function(BuildContext context, AlarmSettings alarm)?
      actionsBuilder;

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
              if (actionsBuilder != null) ...[
                actionsBuilder!(context, first),
                const SizedBox(height: 20),
              ],
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
