import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';

// --- Offset math shared by the wake & bedtime ±1h dialogs (pure & tested).

/// Move a signed offset (minutes) by [delta], hard-stopping within ±12h.
int bumpOffset(int current, int delta) => (current + delta).clamp(-720, 720);

/// Whether [current] is already at the ±12h edge in [delta]'s direction — the
/// button is disabled here so a no-op tap gives visible feedback.
bool offsetAtLimit(int current, int delta) =>
    delta < 0 ? current <= -720 : current >= 720;

/// Signed offset of an absolute bedtime [minutes] from [auto], folded to
/// (−720, 720] (±12h is a single clock point).
int signedBedtimeOffset(int minutes, int auto) {
  final off = ((minutes - auto) % 1440 + 1440) % 1440;
  return off > 720 ? off - 1440 : off;
}

void showSettingsSheet(BuildContext context, ArunodayController c) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => _SettingsPage(c: c)),
  );
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({required this.c});

  final ArunodayController c;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  ArunodayController get c => widget.c;
  final _locationScroll = ScrollController();

  /// Briefly forces the scrollbar visible on open (only if the list actually
  /// scrolls), as a "there's more below" cue, then lets it fade.
  bool _flashScrollbar = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFlashScrollbar());
  }

  void _maybeFlashScrollbar() {
    if (!mounted ||
        !_locationScroll.hasClients ||
        _locationScroll.position.maxScrollExtent <= 0) {
      return;
    }
    setState(() => _flashScrollbar = true);
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _flashScrollbar = false);
    });
  }

  @override
  void dispose() {
    _locationScroll.dispose();
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Active "not sleepy" re-ring, if one is pending.
  DateTime? get _delayedUntil {
    final d = c.settings.bedtimeDelayedUntil;
    return (d != null && d.isAfter(DateTime.now())) ? d : null;
  }

  /// Runs on the candidate coords inside the picker, before naming/returning.
  String? _validatePlace(double lat, double lon) {
    if (!Solar.hasDailyDawnAllYear(DateTime.now().year, lat, lon)) {
      return 'No daily dawn here (polar) — Arunoday needs a real dawn.';
    }
    final dup = c.existingLocationSameDawn(lat, lon);
    return dup == null ? null : 'Same dawn as ${dup.name} — already added.';
  }

  Future<void> _addLocation() async {
    final place = await showLocationSearch(context, validate: _validatePlace);
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

  /// Activate a saved location — but refuse polar ones with no daily dawn.
  Future<void> _selectLocation(SavedLocation l) async {
    if (!Solar.hasDailyDawnAllYear(DateTime.now().year, l.lat, l.lon)) {
      _snack('No daily dawn at ${l.name} (polar region) — '
          'Arunoday needs a real dawn.');
      return;
    }
    await c.update(c.settings.copyWith(activeLocationId: () => l.id));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Reason [minuteOfDay] can't be the bedtime (collision), else null.
  String? _bedtimeConflict(int minuteOfDay) {
    final nw = c.nextWake;
    if (nw != null && nw.hour * 60 + nw.minute == minuteOfDay) {
      return "Bedtime can't be the same as the wake alarm.";
    }
    final again = _delayedUntil;
    if (again != null && again.hour * 60 + again.minute == minuteOfDay) {
      return "Bedtime can't be the same as the pending re-ring.";
    }
    return null;
  }

  Future<void> _editOffset() async {
    final current = c.settings.wakeOffsetMinutes;
    final result = await showDialog<int>(
      context: context,
      builder: (_) =>
          _OffsetDialog(initialMinutes: current, nextDawn: _anchorDawn()),
    );
    if (result == null) return;
    final dawn = _anchorDawn();
    final bed = c.bedtimeMinutes;
    if (dawn != null && bed != null) {
      final wakeMin =
          ((dawn.hour * 60 + dawn.minute + result) % 1440 + 1440) % 1440;
      if (wakeMin == bed.round() % 1440) {
        _snack("Wake time can't be the same as the bedtime.");
        return;
      }
    }
    await c.update(c.settings.copyWith(wakeOffsetMinutes: result));
  }

  /// The exact dawn that produced the next wake = `nextWake − offset`.
  /// (Do NOT recompute `dawnOn(nextWake)`: nextWake's calendar day can differ
  /// from the day whose dawn made it, so that recompute lands on a neighbour
  /// day's dawn and reads one minute off — the bug that showed 15:23 while
  /// the real dawn/wake was 15:22.)
  DateTime? _anchorDawn() {
    final nw = c.nextWake;
    if (nw != null) {
      return nw.subtract(Duration(minutes: c.settings.wakeOffsetMinutes));
    }
    final now = DateTime.now();
    for (var i = 0; i <= ArunodayController.windowDays; i++) {
      final d = c.dawnOn(now.add(Duration(days: i)));
      if (d != null && d.isAfter(now)) return d;
    }
    return null;
  }

  Future<void> _editBedtime() async {
    final auto = c.plan?.bedtimeMinutes.round();
    // The dialog works in the signed offset directly (like the wake dialog),
    // so ±12h hard-stops symmetrically and −12h stays −12h.
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _BedtimeDialog(
        initialOffset: c.settings.bedtimeOffsetMinutes ?? 0,
        autoMinutes: auto,
      ),
    );
    if (result == null || auto == null) return; // result = signed offset
    final absolute = ((auto + result) % 1440 + 1440) % 1440;
    final conflict = _bedtimeConflict(absolute);
    if (conflict != null) {
      _snack(conflict);
      return;
    }
    await c.update(c.settings.copyWith(
      bedtimeOffsetMinutes: () => result == 0 ? null : result, // 0 → Auto
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = c.settings;
    final plan = c.plan;

    return Scaffold(
      appBar: AppBar(title: Text('SETTINGS', style: text.labelSmall)),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              onLongPress: s.wakeOffsetMinutes == 0
                  ? null
                  : () => c.update(s.copyWith(wakeOffsetMinutes: 0)),
            ),
            if (s.wakeOffsetMinutes != 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Long-press wake offset to reset to dawn.',
                    style: text.bodyMedium),
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
              subtitle: Text(c.bedtimeModeDescription, style: text.bodyMedium),
              trailing: Text(
                c.bedtimeMinutes == null
                    ? '—'
                    : fmtMinutesOfDay(c.bedtimeMinutes!),
                style: text.titleMedium,
              ),
              onTap: _editBedtime,
              onLongPress: s.bedtimeOffsetMinutes == null
                  ? null
                  : () => c.update(
                      s.copyWith(bedtimeOffsetMinutes: () => null)),
            ),
            if (s.bedtimeOffsetMinutes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Long-press bedtime to return to auto.',
                    style: text.bodyMedium),
              ),
            if (_delayedUntil != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bedtime again'),
                subtitle: Text('Not sleepy — tonight only',
                    style: text.bodyMedium),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fmtClock(_delayedUntil!), style: text.titleMedium),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: AppPalette.textSecondary,
                      onPressed: c.cancelBedtimeDelay,
                    ),
                  ],
                ),
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
            // The location list fills the rest of the page and scrolls. The
            // scrollbar stays hidden and fades in only while scrolling (the
            // modern default), so it's never a bright static bar.
            Expanded(
              child: Scrollbar(
                controller: _locationScroll,
                thumbVisibility: _flashScrollbar ? true : null,
                child: ListView(
                  controller: _locationScroll,
                  padding: const EdgeInsets.only(right: 8),
                  children: [
                    for (final l in s.locations)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.name),
                        leading: Icon(
                          l.id == (s.activeLocationId ?? s.locations.first.id)
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 20,
                          color: l.id ==
                                  (s.activeLocationId ?? s.locations.first.id)
                              ? Theme.of(context).colorScheme.primary
                              : AppPalette.textSecondary,
                        ),
                        onTap: () => _selectLocation(l),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          color: AppPalette.textSecondary,
                          onPressed: () => _deleteLocation(l),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (plan != null) ...[
              const SizedBox(height: 12),
              Text(
                'Year here: sleep ${fmtDuration(plan.minSleepMinutes)} '
                '(summer) to ${fmtDuration(plan.maxSleepMinutes)} (winter) — '
                'the natural swing of daylight at this latitude.',
                style: text.bodyMedium,
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteLocation(SavedLocation l) async {
    final s = c.settings;
    final rest = s.locations.where((x) => x.id != l.id).toList();
    // The effective active is activeLocationId, or the first location when it's
    // null (the getter's fallback). Only rewrite the id when the active one is
    // going — and use the Function() form so it can actually be set to null
    // when nothing is left (the old plain setter treated null as "keep").
    final deletingActive = (s.activeLocationId ?? s.locations.first.id) == l.id;
    await c.update(s.copyWith(
      locations: rest,
      activeLocationId: deletingActive
          ? () => (rest.isEmpty ? null : rest.first.id)
          : null,
    ));
    // No locations left → settings is unreachable anyway; leave the page so
    // the user lands back on the empty home screen.
    if (rest.isEmpty && mounted) Navigator.of(context).pop();
  }
}

class _BedtimeDialog extends StatefulWidget {
  const _BedtimeDialog({required this.initialOffset, this.autoMinutes});

  /// Signed offset from auto, −720..720 (the source of truth, like wake).
  final int initialOffset;
  final int? autoMinutes;

  @override
  State<_BedtimeDialog> createState() => _BedtimeDialogState();
}

class _BedtimeDialogState extends State<_BedtimeDialog> {
  late int _offset = widget.initialOffset;

  int get _auto => widget.autoMinutes ?? 22 * 60;
  int get _absolute => ((_auto + _offset) % 1440 + 1440) % 1440;

  /// Bump the signed offset with a symmetric ±12h hard stop — same as wake.
  void _bump(int delta) =>
      setState(() => _offset = bumpOffset(_offset, delta));

  bool _atLimit(int delta) => offsetAtLimit(_offset, delta);

  Future<void> _pickExact() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _absolute ~/ 60, minute: _absolute % 60),
      helpText: 'BEDTIME',
    );
    if (picked != null) {
      // A picked clock time is sign-ambiguous at ±12h; fold to the nearer.
      setState(() => _offset =
          signedBedtimeOffset(picked.hour * 60 + picked.minute, _auto));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final auto = widget.autoMinutes;
    return AlertDialog(
      title: Text('BEDTIME', style: text.labelSmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _pickExact,
            child: Text(fmtMinutesOfDay(_absolute.toDouble()),
                style: text.displayLarge),
          ),
          const SizedBox(height: 8),
          Text(
            '${auto == null ? 'manual' : 'auto is ${fmtMinutesOfDay(auto.toDouble())}'}'
            ' · tap the time to pick exactly',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, delta) in [('−1h', -60), ('+1h', 60)])
                OutlinedButton(
                  onPressed: _atLimit(delta) ? null : () => _bump(delta),
                  child: Text(label),
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
          onPressed: () => Navigator.pop(context, _offset),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _OffsetDialog extends StatefulWidget {
  const _OffsetDialog({required this.initialMinutes, this.nextDawn});

  final int initialMinutes;
  final DateTime? nextDawn;

  @override
  State<_OffsetDialog> createState() => _OffsetDialogState();
}

class _OffsetDialogState extends State<_OffsetDialog> {
  late int _minutes = widget.initialMinutes;

  /// Clamped to ±12h: beyond that an "offset from dawn" loses its meaning
  /// (a day-D wake lands on day D+1 and collides with D+1's own wake).
  /// The wake-time picker naturally lands in the same range.
  void _bump(int delta) =>
      setState(() => _minutes = bumpOffset(_minutes, delta));

  /// Pick the desired wake clock time; the dawn offset is back-computed
  /// (wrapped to the nearest half-day, so 04:30 before a 05:36 dawn = −1:06).
  Future<void> _pickWakeTime() async {
    final dawn = widget.nextDawn;
    if (dawn == null) return;
    final dawnM = dawn.hour * 60 + dawn.minute;
    final currentWake = ((dawnM + _minutes) % 1440 + 1440) % 1440;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: currentWake ~/ 60, minute: currentWake % 60),
      helpText: 'WAKE TIME',
    );
    if (picked != null) {
      final delta =
          ((picked.hour * 60 + picked.minute - dawnM + 720) % 1440 + 1440) %
                  1440 -
              720;
      setState(() => _minutes = delta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('WAKE OFFSET', style: text.labelSmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: widget.nextDawn == null ? null : _pickWakeTime,
            child: Text(fmtOffset(_minutes), style: text.displayLarge),
          ),
          const SizedBox(height: 8),
          Text(
            widget.nextDawn == null
                ? 'relative to civil dawn'
                : 'dawn ${fmtClock(widget.nextDawn!)}'
                    ' · wake ${fmtClock(widget.nextDawn!.add(Duration(minutes: _minutes)))}',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (widget.nextDawn != null) ...[
            const SizedBox(height: 2),
            Text('tap the offset to pick the wake time',
                style: text.bodyMedium, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, delta) in [('−1h', -60), ('+1h', 60)])
                OutlinedButton(
                  onPressed:
                      offsetAtLimit(_minutes, delta) ? null : () => _bump(delta),
                  child: Text(label),
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
