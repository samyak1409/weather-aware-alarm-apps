import 'package:alarm/alarm.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';

/// Bedtime-ritual action shown on the ring screen for bedtime alarms
/// (ids 2000-2999): "not sleepy" — stop the ring, ring bedtime again in an
/// hour. (Tomorrow-wake shifting was removed 2026-07-12; see SPEC.md.)
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
    // Stop first — the resync inside delayBedtime re-schedules the whole
    // 7-day window and takes a moment; the ring must die instantly.
    await Alarm.stop(ringingAlarm.id);
    await controller.delayBedtime(d);
  }

  /// A post-midnight bedtime wakes you the same calendar day.
  static bool _isToday(DateTime t) {
    final now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final nextWake = controller.nextWake;

    return Column(
      children: [
        if (nextWake != null) ...[
          Text(
            'WAKE ${_isToday(nextWake) ? 'TODAY' : 'TOMORROW'} '
            '${fmtClock(nextWake)}',
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
              onPressed: () => _delay(context, const Duration(hours: 1)),
              child: const Text('+1h'),
            ),
          ],
        ),
      ],
    );
  }
}
