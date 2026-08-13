import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'ids.dart';
import 'messages.dart';

/// Bedtime-ritual action shown on the ring screen for bedtime alarms (the
/// [ArunodayIds] bedtime range, daily rings plus the re-ring): "sleep late" —
/// stop the ring, ring bedtime again in an hour. (Tomorrow-wake shifting was
/// removed 2026-07-12; see SPEC.md.)
///
/// **It said `NOT SLEEPY` until 2026-08-13** (Samyak). The button is for the
/// night you still have something to finish, and naming it after a feeling
/// made it read as an excuse — the opposite of what an app built on keeping
/// the dawn should say to you at bedtime. `SLEEP LATE` names the choice.
class BedtimeActions extends StatelessWidget {
  const BedtimeActions({
    super.key,
    required this.controller,
    required this.ringingAlarm,
  });

  final ArunodayController controller;
  final AlarmSettings ringingAlarm;

  static bool isBedtimeAlarm(AlarmSettings a) => ArunodayIds.isBedtime(a.id);

  static const Duration _push = Duration(hours: 1);

  Future<void> _delay(BuildContext context, Duration d) async {
    // Stop first — the resync inside delayBedtime re-schedules the whole
    // 7-day window and takes a moment; the ring must die instantly.
    await Alarm.stop(ringingAlarm.id);
    // A push on an AGAIN is the next call up, not another second one — the id
    // is the only place that difference is knowable (2026-08-13).
    await controller.delayBedtime(
      d,
      fromReRing: ringingAlarm.id == ArunodayIds.bedtimeAgain,
    );
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
        // Gone once there is no room left before the wake — see
        // [ArunodayController.canDelayBedtime]. A disabled button would only
        // ask the question again; STOP is the whole screen at that point,
        // which is itself the answer.
        if (controller.canDelayBedtime(_push))
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('SLEEP LATE', style: text.labelSmall),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _delay(context, _push),
                child: const Text('+1h'),
              ),
            ],
          ),
      ],
    );
  }
}
