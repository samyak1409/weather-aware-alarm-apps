import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

/// Wraps the app and overlays a full-screen stop UI whenever an alarm from
/// the `alarm` package is ringing (i.e. the app is open during ring).
///
/// [actionsBuilder] lets an app add per-alarm actions above the STOP button
/// (e.g. Arunoday's bedtime ritual: delay bedtime, adjust tomorrow's wake).
class RingGate extends StatefulWidget {
  const RingGate({
    super.key,
    required this.appName,
    required this.child,
    this.actionsBuilder,
    this.onRingingChanged,
  });

  final String appName;
  final Widget child;
  final Widget Function(BuildContext context, AlarmSettings alarm)?
      actionsBuilder;

  /// Called whenever the set of ringing alarms changes — a ring starting, or
  /// ending (incl. the STOP button here). Apps hook their resync so history
  /// and next-alarm state update the moment a ring begins/ends instead of on
  /// the next app open. Never fires on iOS: rings there are AlarmKit's, so
  /// `Alarm.ringing` stays empty (resync-on-resume covers that platform).
  final VoidCallback? onRingingChanged;

  @override
  State<RingGate> createState() => _RingGateState();
}

class _RingGateState extends State<RingGate> {
  StreamSubscription<AlarmSet>? _sub;
  Set<int> _lastIds = const {};

  @override
  void initState() {
    super.initState();
    // Alarm.ringing replays its current value on subscribe: a quiet mount
    // (empty set == _lastIds) fires nothing, while mounting DURING a ring —
    // opening the app from the ring notification — fires immediately, which
    // is exactly when the app wants a resync.
    _sub = Alarm.ringing.listen((set) {
      final ids = set.alarms.map((a) => a.id).toSet();
      final changed =
          ids.length != _lastIds.length || !ids.containsAll(_lastIds);
      _lastIds = ids;
      if (changed) widget.onRingingChanged?.call();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AlarmSet>(
      stream: Alarm.ringing,
      builder: (context, snapshot) {
        final ringing = snapshot.data?.alarms ?? const <AlarmSettings>{};
        if (ringing.isEmpty) return widget.child;
        return _RingScreen(
          appName: widget.appName,
          alarms: ringing.toList(),
          actionsBuilder: widget.actionsBuilder,
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
              // The alarm's scheduled time, not the wall clock: rings can
              // start a second early and this screen doesn't rebuild.
              Text(fmtClock(first.dateTime), style: text.displayLarge),
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
