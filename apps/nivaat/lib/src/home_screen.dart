import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'alarm_sheet.dart';
import 'background_banner.dart';
import 'controller.dart';
import 'courts_sheet.dart';
import 'engine.dart';
import 'history_sheet.dart';
import 'screenshot_harness.dart';
import 'settings_sheet.dart';

/// Home footer caveat (MESSAGES.md N10). Soft-wrap only — no hard `\n`
/// (large accessibility text must reflow cleanly).
@visibleForTesting
const String nivaatBackgroundNote =
    'Keep the phone charged and online before your '
    'alarm — the background wind check needs both.';

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
    if (kScreenshotHarness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(runScreenshotHarness(context, c));
      });
    }
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
                  // Sound, courts, and history live in settings now
                  // (2026-07-20, Samyak: one entry point is cleaner); the
                  // last-outcome line below doubles as a history shortcut.
                  IconButton(
                    icon: const Icon(Icons.tune, size: 20),
                    color: AppPalette.textSecondary,
                    onPressed: () => showSettingsSheet(context, c),
                  ),
                ],
              ),
            ),
            if (!kScreenshotHarness) ...[
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
            ],
            if (c.history.isNotEmpty) _lastOutcome(text),
            Expanded(
              child: c.alarms.isEmpty ? _empty(text) : _list(text),
            ),
            // Only once there's an alarm — the intro empty state shouldn't
            // nag about background checks before anything is scheduled.
            if (c.alarms.isNotEmpty) _bgNote(text),
            const CraftedBy(accent: AppPalette.wind),
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
    // Top pad: mid-scroll alarm rows sit flush at the Expanded bottom edge,
    // so without air here they kiss this fixed footer (2026-07-22: was 0).
    // Bottom pad lifts the note off CraftedBy without moving the mark
    // (2026-07-20, Samyak: was reading too tight). Soft-wrap only — hard
    // newlines forced a 3-line shape at default scale but overflowed under
    // large accessibility text (2026-07-21).
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 88, 32),
      child: Text(
        nivaatBackgroundNote,
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
    // The line is the newest history row — tapping it opens the full log.
    // Bottom pad keeps scrolling alarm rows from kissing this fixed line
    // (2026-07-22: was 8 — too tight with a long list).
    return InkWell(
      onTap: () => showHistorySheet(context, c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
        child: Text(
          '$when — $line${watching == null ? '' : ' · $watching'}',
          style: text.bodyMedium,
        ),
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
    // Same flash-on-open-if-overflowing cue as settings / history
    // (2026-07-22: many alarms made the home list feel "cut off").
    return FlashingScrollbar(
      builder: (scroll) => ListView.separated(
        controller: scroll,
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
      ),
    );
  }
}
