import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final ArunodayController controller;

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
    final place = await showLocationSearch(context, validate: (lat, lon) {
      if (!Solar.hasDailyDawnAllYear(DateTime.now().year, lat, lon)) {
        return 'No daily dawn here (polar) — Arunoday needs a real dawn.';
      }
      final dup = c.existingLocationSameDawn(lat, lon);
      return dup == null ? null : 'Same dawn as ${dup.name} — already added.';
    });
    if (place == null || !mounted) return;
    final loc = SavedLocation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: place.name,
      lat: place.lat,
      lon: place.lon,
    );
    await c.update(c.settings.copyWith(
      locations: [...c.settings.locations, loc],
      activeLocationId: loc.id,
    ));
  }

  /// Active "not sleepy" re-ring, if one is pending.
  DateTime? get _delayedUntil {
    final d = c.settings.bedtimeDelayedUntil;
    return (d != null && d.isAfter(DateTime.now())) ? d : null;
  }

  /// " · AUTO" / " · AUTO +2:00": how the bedtime relates to the auto plan,
  /// mirroring the wake line's "DAWN +0:00" (offset hidden when it IS auto).
  String _bedtimeModeLabel() => ' · ${c.bedtimeModeDescription.toUpperCase()}';

  /// " · IN 7H 22M" until [t], minute-truncated to match the clocks.
  static String _inLabel(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final mins = DateTime(t.year, t.month, t.day, t.hour, t.minute)
        .difference(DateTime(now.year, now.month, now.day, now.hour, now.minute))
        .inMinutes;
    if (mins < 0) return '';
    return ' · IN ${fmtDuration(mins.toDouble()).toUpperCase()}';
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
          child: loc == null
              ? _empty(text)
              : c.activeLocationHasNoDawn
                  ? _noDawn(text, loc)
                  : _main(text, loc),
        ),
      ),
    );
  }

  Widget _noDawn(TextTheme text, SavedLocation loc) {
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
        const Spacer(),
        Text('No daily dawn at ${loc.name}.', style: text.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'This is a polar location where the sun does not cross the dawn '
          'threshold every day. Pick another location in settings.',
          style: text.bodyMedium,
        ),
        const Spacer(flex: 2),
      ],
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
        const Spacer(),
        Text(
          nextWake == null ? '—' : fmtClock(nextWake),
          style: text.displayLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'WAKE · DAWN${fmtOffset(offset)}'
          '${c.settings.wakeEnabled ? _inLabel(nextWake) : ' · OFF'}',
          style: text.labelSmall,
        ),
        const SizedBox(height: 40),
        Text(
          bed == null ? '—' : fmtMinutesOfDay(bed),
          style: text.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'BEDTIME'
          '${_bedtimeModeLabel()}'
          '${_delayedUntil != null ? ' · AGAIN ${fmtClock(_delayedUntil!)}' : ''}'
          '${sleep == null ? '' : ' · ${fmtDuration(sleep).toUpperCase()} TONIGHT'}'
          // IN (enabled) and OFF (disabled) are opposites — same final slot.
          '${c.settings.bedtimeEnabled ? _inLabel(c.nextBedtimeRing) : ' · OFF'}',
          style: text.labelSmall,
        ),
        const Spacer(flex: 2),
        if (dawnShown != null) ...[
          Text(
            'Dawn ${dawnRolled ? 'tomorrow' : 'today'} ${fmtClock(dawnShown)}'
            '${sunriseShown == null ? '' : ' · Sunrise ${fmtClock(sunriseShown)}'}',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(loc.name, style: text.bodyMedium),
        ],
        const SizedBox(height: 28),
      ],
    );
  }
}
