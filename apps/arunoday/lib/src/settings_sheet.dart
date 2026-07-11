import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';

void showSettingsSheet(BuildContext context, ArunodayController c) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SettingsSheet(c: c),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.c});

  final ArunodayController c;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  ArunodayController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
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

  Future<void> _editOffset() async {
    final current = c.settings.wakeOffsetMinutes;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _OffsetDialog(initialMinutes: current),
    );
    if (result != null) {
      await c.update(c.settings.copyWith(wakeOffsetMinutes: result));
    }
  }

  Future<void> _editBedtime() async {
    final auto = c.plan?.bedtimeMinutes;
    final current = c.bedtimeMinutes ?? 22 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: current.round() ~/ 60, minute: current.round() % 60),
      helpText: auto == null
          ? 'BEDTIME'
          : 'BEDTIME · AUTO IS ${fmtMinutesOfDay(auto)}',
    );
    if (picked != null) {
      await c.update(c.settings.copyWith(
        bedtimeOverrideMinutes: () => picked.hour * 60 + picked.minute,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = c.settings;
    final plan = c.plan;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SETTINGS', style: text.labelSmall),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wake alarm'),
              value: s.wakeEnabled,
              onChanged: (v) => c.update(s.copyWith(wakeEnabled: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bedtime alarm'),
              value: s.bedtimeEnabled,
              onChanged: (v) => c.update(s.copyWith(bedtimeEnabled: v)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wake offset from dawn'),
              trailing: Text(fmtOffset(s.wakeOffsetMinutes),
                  style: text.titleMedium),
              onTap: _editOffset,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarm sound'),
              trailing: Text(
                SoundLibrary.displayName(s.soundPath,
                    defaultName: 'Dawn Bells'),
                style: text.titleMedium,
              ),
              onTap: () async {
                final picked = await showSoundPicker(context,
                    selectedPath:
                        s.soundPath ?? 'assets/sounds/arunoday_dawn.wav');
                if (picked != null) {
                  await c.update(
                      c.settings.copyWith(soundPath: () => picked.path));
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bedtime'),
              subtitle: Text(
                s.bedtimeOverrideMinutes == null ? 'Auto' : 'Manual',
                style: text.bodyMedium,
              ),
              trailing: Text(
                c.bedtimeMinutes == null
                    ? '—'
                    : fmtMinutesOfDay(c.bedtimeMinutes!),
                style: text.titleMedium,
              ),
              onTap: _editBedtime,
              onLongPress: s.bedtimeOverrideMinutes == null
                  ? null
                  : () => c.update(
                      s.copyWith(bedtimeOverrideMinutes: () => null)),
            ),
            if (s.bedtimeOverrideMinutes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Long-press bedtime to return to auto.',
                    style: text.bodyMedium),
              ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('LOCATIONS', style: text.labelSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  color: AppPalette.textSecondary,
                  onPressed: _addLocation,
                ),
              ],
            ),
            ...s.locations.map(
              (l) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.name),
                leading: Icon(
                  l.id == (s.activeLocationId ?? s.locations.first.id)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: l.id == (s.activeLocationId ?? s.locations.first.id)
                      ? Theme.of(context).colorScheme.primary
                      : AppPalette.textSecondary,
                ),
                onTap: () => c.update(s.copyWith(activeLocationId: l.id)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: AppPalette.textSecondary,
                  onPressed: () {
                    final rest =
                        s.locations.where((x) => x.id != l.id).toList();
                    c.update(s.copyWith(
                      locations: rest,
                      activeLocationId: s.activeLocationId == l.id
                          ? (rest.isEmpty ? null : rest.first.id)
                          : s.activeLocationId,
                    ));
                  },
                ),
              ),
            ),
            if (plan != null) ...[
              const SizedBox(height: 12),
              Text(
                'Year at this location: sleep '
                '${fmtDuration(plan.minSleepMinutes)} (summer) to '
                '${fmtDuration(plan.maxSleepMinutes)} (winter).'
                '${plan.feasible ? '' : ' No fixed bedtime fits 7–9h here; showing closest compromise.'}',
                style: text.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OffsetDialog extends StatefulWidget {
  const _OffsetDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_OffsetDialog> createState() => _OffsetDialogState();
}

class _OffsetDialogState extends State<_OffsetDialog> {
  late int _minutes = widget.initialMinutes;

  void _bump(int delta) => setState(() => _minutes += delta);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('WAKE OFFSET', style: text.labelSmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(fmtOffset(_minutes), style: text.displayLarge),
          const SizedBox(height: 8),
          Text('relative to civil dawn', style: text.bodyMedium),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (label, delta) in [
                ('−1h', -60),
                ('−15m', -15),
                ('+15m', 15),
                ('+1h', 60),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    onPressed: () => _bump(delta),
                    child: Text(label),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _minutes),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
