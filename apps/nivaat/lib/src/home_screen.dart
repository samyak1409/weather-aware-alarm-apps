import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'alarm_sheet.dart';
import 'controller.dart';
import 'courts_sheet.dart';
import 'engine.dart';
import 'history_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final NivaatController controller;

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
            if (c.history.isNotEmpty) _lastOutcome(text),
            Expanded(
              child: c.alarms.isEmpty ? _empty(text) : _list(text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lastOutcome(TextTheme text) {
    final h = c.history.first;
    final line = switch (h.outcome) {
      CheckOutcome.rang =>
        'Rang at ${(h.volume! * 100).round()}% · wind ${h.courtSpeedKmh!.toStringAsFixed(1)} km/h',
      CheckOutcome.skippedWindy =>
        'Skipped · wind ${h.courtSpeedKmh!.toStringAsFixed(1)} km/h',
      CheckOutcome.skippedGusty =>
        'Skipped · gusts ${h.rawGustKmh!.toStringAsFixed(0)} km/h',
      CheckOutcome.skippedNoData => 'Skipped · could not check wind',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      child: Text(
        '${fmtShortDate(h.at)} ${fmtClock(h.at)} — $line',
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
