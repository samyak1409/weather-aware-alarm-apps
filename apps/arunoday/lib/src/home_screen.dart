import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'messages.dart';
import 'notifications.dart';
import 'screenshot_harness.dart';
import 'settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.permissionFlow,
  });

  final ArunodayController controller;

  /// The startup notification-permission request; its completion re-checks
  /// the denied-banner (see [NotificationPermissionBanner.recheckAfter]).
  final Future<void>? permissionFlow;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  ArunodayController get c => widget.controller;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onChanged);
    // The "in Xh Ym" countdowns age by the minute.
    _ticker = Timer.periodic(
        const Duration(minutes: 1), (_) => _onChanged());
    if (kScreenshotHarness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(runScreenshotHarness(context, c));
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.resync();
  }

  Future<void> _addLocation() async {
    final place = await showLocationSearch(context, validate: c.placeRefusal);
    if (place == null || !mounted) return;
    final loc = SavedLocation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: place.name,
      lat: place.lat,
      lon: place.lon,
    );
    await c.update(c.settings.copyWith(
      locations: [...c.settings.locations, loc],
      activeLocationId: () => loc.id,
    ));
  }

  /// Active "not sleepy" re-ring, if one is pending.
  DateTime? get _delayedUntil {
    final d = c.settings.bedtimeDelayedUntil;
    return (d != null && d.isAfter(DateTime.now())) ? d : null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!c.loaded) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final loc = c.activeLocation;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Expanded(
                child: loc == null ? _empty(text) : _main(text, loc),
              ),
              // Below every branch, so the maker's mark never disappears.
              const CraftedBy(accent: AppPalette.dawn),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('ARUNODAY', style: text.labelSmall),
        const Spacer(),
        Text('Wake with the dawn.', style: text.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Add your location — the alarm follows its real dawn, every day of the year.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.tonal(
          onPressed: _addLocation,
          child: const Text('Add location'),
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _main(TextTheme text, SavedLocation loc) {
    final nextWake = c.nextWake;
    // Footer shows today's dawn until sunrise has passed, then tomorrow's.
    final now = DateTime.now();
    var dawnShown = c.dawnOn(now);
    var sunriseShown = c.sunriseOn(now);
    final dawnRolled = sunriseShown != null && !sunriseShown.isAfter(now);
    if (dawnRolled) {
      final tomorrow = now.add(const Duration(days: 1));
      dawnShown = c.dawnOn(tomorrow);
      sunriseShown = c.sunriseOn(tomorrow);
    }
    final bed = c.bedtimeMinutes;
    final sleep = c.tonightSleepMinutes;
    final offset = c.settings.wakeOffsetMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Text('ARUNODAY', style: text.labelSmall),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.tune, size: 20),
              color: AppPalette.textSecondary,
              onPressed: () => showSettingsSheet(context, c),
            ),
          ],
        ),
        if (!kScreenshotHarness) ...[
          // Armed-home only (location set) — empty intro stays clean
          // (2026-07-22, same rule as Nivaat's ≥1-alarm gate).
          const AlarmPermissionBanner(
            appName: 'Arunoday',
            accent: AppPalette.dawn,
            margin: EdgeInsets.only(top: 16, bottom: 4),
          ),
          // Android-only: the iOS rings are AlarmKit's own full-screen alerts,
          // so Arunoday posts nothing through this permission there. On Android
          // a denied permission leaves the ring as bare sound — no card, no
          // full-screen, no Stop outside the app.
          if (Platform.isAndroid)
            NotificationPermissionBanner(
              accent: AppPalette.dawn,
              margin: const EdgeInsets.only(top: 16, bottom: 4),
              denied: notificationsDenied,
              recheckAfter: widget.permissionFlow,
              message: kArunodayNotificationsOff,
            ),
        ],
        const Spacer(),
        // The `—` on both clocks is defence, not a state you can reach: this
        // whole branch needs a location, and a location with no daily dawn is
        // refused when you add it (A16), so dawn — and everything derived from
        // it — resolves. No-location is the empty intro above (A9), which is
        // what the doc used to mis-describe this as. Kept because the honest
        // alternative is `nextWake!`, and this repo already has one scar from
        // force-unwrapping an optional that "couldn't" be null (N4's volume,
        // which made history permanently un-openable).
        Text(
          nextWake == null ? '—' : fmtClock(nextWake),
          style: text.displayLarge,
        ),
        const SizedBox(height: 4),
        Text(
          arunodayWakeLine(
            offsetMinutes: offset,
            enabled: c.settings.wakeEnabled,
            nextWake: nextWake,
          ),
          style: text.labelSmall,
        ),
        const SizedBox(height: 40),
        Text(
          bed == null ? '—' : fmtMinutesOfDay(bed),
          style: text.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          arunodayBedtimeLine(
            mode: c.bedtimeModeDescription,
            enabled: c.settings.bedtimeEnabled,
            again: _delayedUntil,
            sleepMinutes: sleep,
            nextRing: c.nextBedtimeRing,
          ),
          style: text.labelSmall,
        ),
        const Spacer(flex: 2),
        if (dawnShown != null) ...[
          Text(
            arunodayFooterLine(dawnShown, sunriseShown, rolled: dawnRolled),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(loc.name, style: text.bodyMedium),
        ],
        // Gap above CraftedBy — keep the mark parked, push the dawn/location
        // lines up (2026-07-20, Samyak: was reading too tight).
        const SizedBox(height: 40),
      ],
    );
  }
}
