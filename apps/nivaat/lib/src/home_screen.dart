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

  /// Fires when an active "+30m still checking" window ends so the home cue
  /// clears without waiting for the next resync.
  Timer? _watchExpiry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onChanged);
    _armWatchExpiry();
    if (kScreenshotHarness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(runScreenshotHarness(context, c));
      });
    }
  }

  @override
  void dispose() {
    _watchExpiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _armWatchExpiry();
    setState(() {});
  }

  void _armWatchExpiry() {
    _watchExpiry?.cancel();
    _watchExpiry = null;
    // Same pick as the cue text — clears with late ring / alarm gone too.
    final open = nivaatSoonestOpenWatch(
      c.history,
      alarms: c.alarms,
      checkStates: c.checkStates.values,
    );
    final until = open?.watchedUntil;
    if (until == null) return;
    final delay = until.difference(DateTime.now());
    _watchExpiry = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      // Re-arm: another alarm may still be inside its +30m window.
      _armWatchExpiry();
      setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background isolates write history the UI isolate's prefs cache can't
    // see — pull on every resume (bg checks also ping via ui_resync).
    if (state == AppLifecycleState.resumed) unawaited(c.resync());
  }

  Future<void> _addAlarm() async {
    // No court yet: bootstrap via place picker, then open the alarm editor
    // (courts sheet auto-dismisses after the first save — Settings keeps the
    // list open when adding from there).
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
    final watchingLine = nivaatHomeWatchingLine(
      c.history,
      alarms: c.alarms,
      checkStates: c.checkStates.values,
    );

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
                  // (2026-07-20, Samyak: one entry point is cleaner); a live
                  // "still checking" cue below doubles as a history shortcut
                  // only while the +30m window is open (2026-07-22).
                  IconButton(
                    icon: const Icon(Icons.tune, size: 20),
                    color: AppPalette.textSecondary,
                    onPressed: () => showSettingsSheet(context, c),
                  ),
                ],
              ),
            ),
            // Permission nudges only once there's something to protect
            // (2026-07-22: keep the intro hero clean — same rule as Arunoday).
            if (!kScreenshotHarness && c.alarms.isNotEmpty) ...[
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
            if (watchingLine != null) _watchingCue(text, watchingLine),
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
        style: text.bodyMedium!.copyWith(
          fontSize: 12,
          // Quieter than body secondary — a standing caveat, not a headline
          // (2026-07-22, Samyak: was competing with the alarm list).
          color: AppPalette.textSecondary.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  /// Live "+30m still checking" cue only (MESSAGES N21). Tap → full history.
  ///
  /// Leading wind-accent ● in the text run (not a separate widget) — "live +
  /// tappable" without a word prefix. Full-width [InkWell] so a short line
  /// still highlights edge-to-edge. Outer bottom 8 + ink bottom 8 keeps the
  /// same 16px gap to the list.
  Widget _watchingCue(TextTheme text, String line) {
    final body = text.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showHistorySheet(context, c),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
              child: Text.rich(
                TextSpan(
                  style: body,
                  children: [
                    TextSpan(
                      text: '● ',
                      style: body.copyWith(color: AppPalette.wind),
                    ),
                    TextSpan(text: line),
                  ],
                ),
              ),
            ),
          ),
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
