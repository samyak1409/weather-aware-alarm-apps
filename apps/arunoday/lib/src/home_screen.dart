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

  Future<void> _addLocation() async {
    final place = await showLocationSearch(context);
    if (place == null) return;
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
          child: loc == null ? _empty(text) : _main(text, loc),
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
    final dawnToday = c.dawnOn(DateTime.now());
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
          'WAKE · DAWN ${fmtOffset(offset)}'
          '${c.settings.wakeEnabled ? '' : ' · OFF'}',
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
          '${c.settings.bedtimeOverrideMinutes != null ? ' · MANUAL' : ''}'
          '${sleep == null ? '' : ' · ${fmtDuration(sleep).toUpperCase()} TONIGHT'}'
          '${c.settings.bedtimeEnabled ? '' : ' · OFF'}',
          style: text.labelSmall,
        ),
        const Spacer(flex: 2),
        if (dawnToday != null)
          Text(
            'Dawn today ${fmtClock(dawnToday)} · ${loc.name}',
            style: text.bodyMedium,
          ),
        const SizedBox(height: 28),
      ],
    );
  }
}
