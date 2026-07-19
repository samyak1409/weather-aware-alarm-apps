import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'alarm_sheet.dart';
import 'background_banner.dart';
import 'controller.dart';
import 'courts_sheet.dart';
import 'engine.dart';
import 'history_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.permissionFlow,
    this.batteryFlow,
  });

  final NivaatController controller;

  /// The startup notification-permission request; its completion re-checks
  /// the denied-banner (see [NotificationPermissionBanner.recheckAfter]).
  final Future<void>? permissionFlow;

  /// The startup battery-exemption once-ask; its completion re-checks the
  /// background-checks banner (see [BackgroundChecksBanner.recheckAfter]).
  final Future<void>? batteryFlow;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  NivaatController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.resync();
  }

  Future<void> _addAlarm() async {
    if (c.courts.isEmpty) {
      final added = await showCourtsSheet(context, c, promptAdd: true);
      if (!added || !mounted) return;
    }
    await showAlarmSheet(context, c, alarm: null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!c.loaded) return const Scaffold(body: SizedBox.shrink());

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addAlarm,
        backgroundColor: AppPalette.wind,
        foregroundColor: AppPalette.trueBlack,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
              child: Row(
                children: [
                  Text('NIVAAT', style: text.labelSmall),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.music_note_outlined, size: 20),
                    color: AppPalette.textSecondary,
                    onPressed: () async {
                      final current = await c.store.loadSoundPath();
                      if (!context.mounted) return;
                      final picked = await showSoundPicker(context,
                          selectedPath: current ?? nivaatDefaultSound);
                      if (picked != null) {
                        await c.store.saveSoundPath(picked.path);
                        nivaatSelectedSound = picked.path;
                        await c.resync();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.history, size: 20),
                    color: AppPalette.textSecondary,
                    onPressed: () => showHistorySheet(context, c),
                  ),
                  IconButton(
                    icon: const Icon(Icons.place_outlined, size: 20),
                    color: AppPalette.textSecondary,
                    onPressed: () => showCourtsSheet(context, c),
                  ),
                ],
              ),
            ),
            const AlarmPermissionBanner(
                appName: 'Nivaat', accent: AppPalette.wind),
            NotificationPermissionBanner(
              accent: AppPalette.wind,
              denied: () =>
                  c.engine.notifier?.notificationsDenied() ??
                  Future.value(false),
              recheckAfter: widget.permissionFlow,
              message: Platform.isAndroid
                  ? 'Notifications are off — a ringing alarm shows nothing '
                      'on screen (sound only, no Stop), and Nivaat can\'t '
                      'tell you when it skips an alarm for wind, or why.'
                  : 'Notifications are off — Nivaat can\'t tell you when it '
                      'skips an alarm for wind, or why.',
            ),
            BackgroundChecksBanner(recheckAfter: widget.batteryFlow),
            if (c.history.isNotEmpty) _lastOutcome(text),
            Expanded(
              child: c.alarms.isEmpty ? _empty(text) : _list(text),
            ),
            _bgNote(text),
          ],
        ),
      ),
    );
  }

  /// Standing caveat, both platforms: the pre-alarm wind check is background
  /// work, so it needs power and a network. Android throttles background
  /// wakeups under battery saver; iOS only grants BGAppRefresh opportunistically
  /// and Low Power Mode suppresses it outright. Right-padded to clear the FAB.
  Widget _bgNote(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 88, 12),
      child: Text(
        'Keep the phone charged and online before your alarm — '
        'the background wind check needs both.',
        style: text.bodyMedium!.copyWith(fontSize: 12),
      ),
    );
  }

  Widget _lastOutcome(TextTheme text) {
    final h = c.history.first;
    final line = switch (h.outcome) {
      CheckOutcome.rang =>
        'Rang (at ${(h.volume! * 100).round()}%) · ${h.windGustSummary}',
      CheckOutcome.skippedWindy => 'Skipped (windy) · ${h.windGustSummary}',
      CheckOutcome.skippedGusty => 'Skipped (gusty) · ${h.windGustSummary}',
      CheckOutcome.skippedNoData => 'Skipped (no data)',
    };
    final verb = h.outcome == CheckOutcome.skippedNoData ? 'last tried' : 'checked';
    final court = c.courtById(h.courtId)?.name ?? '—';
    final watching = nivaatStillWatchingNote(h);
    final when = '$court · ${fmtShortDate(h.at)} ${fmtClock(h.at)} · '
        '$verb ${fmtCheckTime(h.whenChecked, h.at)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      child: Text(
        '$when — $line${watching == null ? '' : ' · $watching'}',
        style: text.bodyMedium,
      ),
    );
  }

  Widget _empty(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('The windless alarm.', style: text.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Rings only when the wind at your court is low enough to play. '
            'The calmer the morning, the louder it rings.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _list(TextTheme text) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 96),
      itemCount: c.alarms.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final a = c.alarms[i];
        final court = c.courtById(a.courtId);
        return InkWell(
          onTap: () => showAlarmSheet(context, c, alarm: a),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}',
                        style: text.headlineMedium!.copyWith(
                          color: a.enabled
                              ? AppPalette.textPrimary
                              : AppPalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${fmtWeekdays(a.weekdays)} · ${court?.name ?? 'court removed'} · ≤${a.courtSpeedLimitKmh} km/h',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: a.enabled,
                  onChanged: (v) => c.toggleAlarm(a.id, v),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
