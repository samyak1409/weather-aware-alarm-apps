import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'ids.dart';
import 'messages.dart';

/// Bedtime-ritual action shown on the ring screen for bedtime alarms (the
/// [ArunodayIds] bedtime range, daily rings plus the re-ring): "not sleepy" —
/// stop the ring, ring bedtime again in an hour. (Tomorrow-wake shifting was
/// removed 2026-07-12; see SPEC.md.)
class BedtimeActions extends StatelessWidget {
  const BedtimeActions({
    super.key,
    required this.controller,
    required this.ringingAlarm,
  });

  final ArunodayController controller;
  final AlarmSettings ringingAlarm;

  static bool isBedtimeAlarm(AlarmSettings a) => ArunodayIds.isBedtime(a.id);

  Future<void> _delay(BuildContext context, Duration d) async {
    // Stop first — the resync inside delayBedtime re-schedules the whole
    // 7-day window and takes a moment; the ring must die instantly.
    await Alarm.stop(ringingAlarm.id);
    await controller.delayBedtime(d);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final nextWake = controller.nextWake;

    return Column(
      children: [
        if (nextWake != null) ...[
          Text(
            arunodayRitualWakeLine(nextWake),
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
