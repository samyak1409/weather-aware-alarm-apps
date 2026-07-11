import 'package:alarm/alarm.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';

/// Bedtime-ritual actions shown on the ring screen for bedtime alarms
/// (ids 2000-2999): confirm tomorrow's wake, delay bedtime if not sleepy,
/// or push tomorrow's wake later one time.
class BedtimeActions extends StatelessWidget {
  const BedtimeActions({
    super.key,
    required this.controller,
    required this.ringingAlarm,
  });

  final ArunodayController controller;
  final AlarmSettings ringingAlarm;

  static bool isBedtimeAlarm(AlarmSettings a) => a.id >= 2000 && a.id < 3000;

  Future<void> _delay(BuildContext context, Duration d) async {
    await controller.delayBedtime(d);
    await Alarm.stop(ringingAlarm.id);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final nextWake = controller.nextWake;
    final extra = controller.settings.oneTimeExtraMinutes;

    return Column(
      children: [
        if (nextWake != null) ...[
          Text(
            'WAKE TOMORROW ${fmtClock(nextWake)}'
            '${extra != 0 ? ' · ONE-TIME ${fmtOffset(extra)}' : ''}',
            style: text.labelSmall,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('NOT SLEEPY', style: text.labelSmall),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _delay(context, const Duration(minutes: 30)),
              child: const Text('+30m'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _delay(context, const Duration(hours: 1)),
              child: const Text('+1h'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('TOMORROW', style: text.labelSmall),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => controller.setOneTimeExtra(extra == 60 ? 0 : 60),
              child: Text(extra == 60 ? '+1h ✓' : '+1h'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () =>
                  controller.setOneTimeExtra(extra == 120 ? 0 : 120),
              child: Text(extra == 120 ? '+2h ✓' : '+2h'),
            ),
          ],
        ),
      ],
    );
  }
}
