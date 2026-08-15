import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'messages.dart';
import 'time_conflict.dart';

/// How long the two settings resets want the press held — **1s, up from
/// Flutter's 500ms `kLongPressTimeout`** (Samyak, 2026-08-13; 1.5s was tried
/// the same day and felt like a wait).
///
/// These are the only gestures in either app that change a saved value with no
/// dialog in front of them, and each one throws away a number you set on
/// purpose. At half a second a press that merely lingered was a reset; a full
/// second has to be meant. Letting go early costs nothing: the tile's own tap
/// wins the arena instead and the picker opens, which reads as "not held" far
/// better than nothing happening would.
const Duration kResetHoldDuration = Duration(seconds: 1);

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

  /// Active "sleep late" re-ring, if one is pending.
  DateTime? get _delayedUntil {
    final d = c.settings.bedtimeDelayedUntil;
    return (d != null && d.isAfter(DateTime.now())) ? d : null;
  }

  Future<void> _addLocation() async {
    // Same refusals as the home screen's add — one copy, on the controller.
    final place = await showLocationSearch(context, validate: c.placeRefusal);
    if (place == null || !mounted) return;
    final loc = place.toSavedLocation();
    await c.update(c.settings.copyWith(
      locations: [...c.settings.locations, loc],
      activeLocationId: () => loc.id,
    ));
  }

  /// Activate a saved location.
  Future<void> _selectLocation(SavedLocation l) async {
    await c.update(c.settings.copyWith(activeLocationId: () => l.id));
  }

  Future<void> _editOffset() async {
    // No dawn = nothing to offset from, so there is no dialog to show. Can't
    // happen from a real screen — the row that calls this is not built without
    // a location (see `hasLocation` in [build]; it used to be that settings
    // itself was unreachable without one), and a location with no daily dawn is
    // refused when you add it (A16) — but opening a picker anchored to nothing
    // is worse than opening none: it silently drops its collision check (see
    // [_OffsetDialogState._conflict]).
    final dawn = _anchorDawn();
    if (dawn == null) return;
    final current = c.settings.wakeOffsetMinutes;
    final bed = c.bedtimeMinutes;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _OffsetDialog(
        initialMinutes: current,
        nextDawn: dawn,
        bedtimeMinuteOfDay: bed?.round(),
        // A callback, not a value: the answer moves with every nudge, and
        // only the controller knows which morning's dawn to hang it off.
        //
        // **Two anchors, because the two lines answer different questions**
        // (Samyak, 2026-08-13). The hint is a CONVERSION — "dawn here is about
        // 06:51, and your offset makes that 07:11" — so it hangs off
        // `nextDawn`, fixed for the life of the dialog; dawn is a fact about
        // the place and near enough constant day to day, so that arithmetic
        // holds whichever morning the alarm lands on. The countdown is a
        // SCHEDULE — "when does this next ring" — so it walks the window.
        //
        // Don't "fix" this into one anchor. Walking the hint too makes a
        // picked wake time come back a minute off, since the pick is mapped
        // against a dawn the new offset may have moved; freezing the countdown
        // instead empties it whenever a drafted offset puts the wake behind
        // you. The one visible artefact is that at a large offset the hint's
        // clock and the countdown's target can differ by a minute — that is
        // dawn drift (~1 min/day), which this app lives with everywhere, and
        // not a symptom of the two anchors.
        draftRing: c.draftWakeRing,
      ),
    );
    // Collision is refused inside the dialog (Save disabled) — a returned
    // value is always safe to apply.
    if (result == null) return;
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
      final d = c.dawnOn(calendarDay(now, i));
      if (d != null && d.isAfter(now)) return d;
    }
    return null;
  }

  /// Long-press "reset to dawn" — **through the same A16 check the dialog
  /// runs** (REVIEW #16). The dialogs refuse a same-minute wake and bedtime by
  /// disabling Save; this wrote straight through, so the one gesture that
  /// skipped validation could arm two alarms on one minute, and the plugin
  /// queues the second so they sound back to back. A refusal says why rather
  /// than doing nothing — a silent no-op reads as a missed press.
  Future<void> _resetWakeOffset() async {
    final dawn = _anchorDawn();
    // No dawn, nothing to collide with — the same reading the builders take
    // whenever the other side is unknown.
    final conflict = dawn == null
        ? null
        : arunodayWakeConflictsWithBedtime(
            wakeOffsetMinutes: 0,
            dawn: dawn,
            bedtimeMinuteOfDay: c.bedtimeMinutes?.round(),
          );
    if (conflict != null) {
      _refuse(conflict);
      return;
    }
    await c.update(c.settings.copyWith(wakeOffsetMinutes: 0));
  }

  /// Long-press "return to auto" — the bedtime half of [_resetWakeOffset].
  Future<void> _resetBedtime() async {
    final auto = c.plan?.bedtimeMinutes.round();
    final wake = c.nextWake;
    final conflict = auto == null
        ? null
        : arunodayBedtimeConflictsWithWake(
            bedtimeMinuteOfDay: auto,
            wakeMinuteOfDay: wake == null ? null : wake.hour * 60 + wake.minute,
          );
    if (conflict != null) {
      _refuse(conflict);
      return;
    }
    await c.update(c.settings.copyWith(bedtimeOffsetMinutes: () => null));
  }

  void _refuse(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editBedtime() async {
    // Same precondition as [_editOffset]: no sleep plan, no anchor, no dialog.
    // The old code opened one anyway, anchored to a fabricated 22:00 — and
    // then discarded whatever you saved, because the write below needs the
    // auto value the dialog didn't have.
    final auto = c.plan?.bedtimeMinutes.round();
    if (auto == null) return;
    final wake = c.nextWake;
    final wakeMinuteOfDay =
        wake == null ? null : wake.hour * 60 + wake.minute;
    // The dialog works in the signed offset directly (like the wake dialog),
    // so ±12h hard-stops symmetrically and −12h stays −12h.
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _BedtimeDialog(
        initialOffset: c.settings.bedtimeOffsetMinutes ?? 0,
        autoMinutes: auto,
        wakeMinuteOfDay: wakeMinuteOfDay,
      ),
    );
    // Collision is refused inside the dialog (Save disabled).
    if (result == null) return; // result = signed offset
    await c.update(c.settings.copyWith(
      bedtimeOffsetMinutes: () => result == 0 ? null : result, // 0 → Auto
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // **Rendering only — nothing a tap runs may read `s`** (REVIEW #20).
    // `c.update` notifies after saving AND re-arming the whole window, so a
    // second tap arrives before this frame is replaced and a `copyWith` on
    // this snapshot undoes the first: switch off Wake, then Bedtime, and Wake
    // comes back on. What this frame SHOWS may use it; anything a callback
    // carries forward — what it writes, what it seeds a picker with — reads
    // `c.settings` at tap time, as the handlers outside `build` already do.
    final s = c.settings;
    final plan = c.plan;
    // **Everything above `Alarm sound` is a question about a place** (2026-08-15,
    // Samyak): a wake offset is measured from a dawn, a bedtime comes out of a
    // sleep plan, and with no location there is neither. Settings opens from
    // the empty home screen now — the way Nivaat's always has — so this page
    // has to render that state rather than assume it away, and the honest
    // rendering is to leave out the rows that would have nothing to say. They
    // come back the moment a location is added, and go again with the last one.
    //
    // It is also what keeps the two pickers' no-anchor branches unreachable
    // (see [_editOffset] and `arunodayBedtimePickerHint`): the rows that open
    // them are not built at all.
    final hasLocation = s.locations.isNotEmpty;
    // The effective active location — the stored id, or the first when it is
    // null, which is the fallback the alarms really follow.
    final activeId =
        hasLocation ? (s.activeLocationId ?? s.locations.first.id) : null;

    return SettingsPage(
      accent: AppPalette.dawn,
      children: [
        // Grouped by ritual: the wake pair, the bedtime pair, then the sound
        // both rings share (2026-07-20 reorder). The whole group needs a
        // location — see [hasLocation].
        if (hasLocation) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wake alarm'),
            value: s.wakeEnabled,
            onChanged: (v) => c.update(c.settings.copyWith(wakeEnabled: v)),
          ),
          _HeldReset(
            onHeld: s.wakeOffsetMinutes == 0 ? null : _resetWakeOffset,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wake offset from dawn'),
              trailing:
                  Text(fmtOffset(s.wakeOffsetMinutes), style: text.titleMedium),
              onTap: _editOffset,
            ),
          ),
          if (s.wakeOffsetMinutes != 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Long-press wake offset to reset to dawn.',
                  style: text.bodyMedium),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bedtime alarm'),
            value: s.bedtimeEnabled,
            onChanged: (v) => c.update(c.settings.copyWith(bedtimeEnabled: v)),
          ),
          _HeldReset(
            onHeld: s.bedtimeOffsetMinutes == null ? null : _resetBedtime,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bedtime'),
              subtitle: Text(c.bedtimeModeDescription, style: text.bodyMedium),
              // `!` — this row only exists with a location, and a location
              // always yields a sleep plan.
              trailing: Text(fmtMinutesOfDay(c.bedtimeMinutes!),
                  style: text.titleMedium),
              onTap: _editBedtime,
            ),
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
              subtitle:
                  Text('Sleep late — tonight only', style: text.bodyMedium),
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
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alarm sound'),
          trailing: Text(
            SoundLibrary.displayName(s.soundPath, defaultName: 'Dawn Bells'),
            style: text.titleMedium,
          ),
          onTap: () async {
            final picked = await showSoundPicker(context,
                selectedPath:
                    c.settings.soundPath ?? 'assets/sounds/arunoday_dawn.wav');
            if (picked != null) {
              await c.update(c.settings.copyWith(soundPath: () => picked.path));
            }
          },
        ),
        const SettingsSection(label: 'APPEARANCE'),
        const HeavyTypeSwitch(),
        const AppIconPicker(
          accent: AppPalette.dawn,
          appName: 'Arunoday',
          choices: [
            AppIconChoice(id: '1', label: 'Horizon', asset: 'assets/icons/1.png'),
            AppIconChoice(id: '2', label: 'Rays', asset: 'assets/icons/2.png'),
            AppIconChoice(id: '3', label: 'Dawn', asset: 'assets/icons/3.png'),
          ],
        ),
        SettingsSection(
          label: 'LOCATIONS',
          onAdd: _addLocation,
          emptyNote: hasLocation ? null : kArunodayNoLocationsYet,
        ),
        for (final l in s.locations)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.name),
            leading: Icon(
              l.id == activeId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 20,
              color: l.id == activeId
                  ? Theme.of(context).colorScheme.primary
                  : AppPalette.textSecondary,
            ),
            onTap: () => _selectLocation(l),
            trailing: PlaceRowActions(
              place: l,
              accent: AppPalette.dawn,
              onDelete: () => _deleteLocation(l),
            ),
          ),
        if (plan != null) ...[
          const SizedBox(height: 12),
          Text(arunodaySleepReadout(plan), style: text.bodyMedium),
        ],
      ],
    );
  }

  /// **Asks first, on every delete** (2026-08-15, Samyak — N20's rule brought
  /// across). One tap on the bin means three different things here, and only
  /// the harmless one is obvious from the row: deleting a spare place changes
  /// nothing, deleting the active one silently re-points every alarm at
  /// another place's dawn, and deleting the last one switches the wake and
  /// bedtime off altogether. [arunodayDeleteLocationWarning] says which.
  Future<void> _deleteLocation(SavedLocation l) async {
    final before = c.settings;
    final restBefore = before.locations.where((x) => x.id != l.id).toList();
    final ok = await confirmDestructive(
      context,
      title: 'DELETE LOCATION',
      message: arunodayDeleteLocationWarning(
        l.name,
        isActive:
            (before.activeLocationId ?? before.locations.first.id) == l.id,
        nextActiveName: restBefore.isEmpty ? null : restBefore.first.name,
      ),
    );
    if (!ok || !mounted) return;
    // **Re-read after the dialog** (REVIEW #20's rule, one await further out):
    // what this writes must be built on the settings as they are now, not on
    // the frame that opened the confirmation. A row tapped twice is the case
    // that matters — the second confirmation must not resurrect the list the
    // first one deleted from.
    final s = c.settings;
    if (!s.locations.any((x) => x.id == l.id)) return;
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
    // **The page stays open with nothing left** (2026-08-15). It used to pop,
    // because settings was unreachable without a location and staying would
    // have stranded the user on a page they could not get back to. Settings
    // opens from the empty home now, so popping would instead throw away the
    // page you were working on — and what is left here is exactly the section
    // you need: LOCATIONS, with its empty state and its `+`.
  }
}

/// [child] with a long press that takes [kResetHoldDuration] rather than
/// Flutter's default.
///
/// Hand-built because there is no duration knob to turn: `ListTile.onLongPress`
/// passes straight to the `InkWell` under it, and neither takes one. The
/// recognizer is an ANCESTOR of the tile and still wins — arena victory is not
/// scoped by depth, and at a full second the tile's own tap recognizer is still waiting
/// for the pointer to come up, so accepting here rejects it.
///
/// [Feedback.forLongPress] is the buzz `InkWell` would have given: on a hold
/// this long it is the only signal that the gesture landed, since what follows
/// is a value quietly changing somewhere else on the page.
class _HeldReset extends StatelessWidget {
  const _HeldReset({required this.onHeld, required this.child});

  /// Null builds no recognizer at all, so a row with nothing to reset cannot
  /// swallow a press — same meaning `onLongPress: null` had on the tile.
  final VoidCallback? onHeld;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final held = onHeld;
    if (held == null) return child;
    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(
              duration: kResetHoldDuration, debugOwner: this),
          (recognizer) => recognizer.onLongPress = () {
            unawaited(Feedback.forLongPress(context));
            held();
          },
        ),
      },
      child: child,
    );
  }
}

/// The pickers' live `in 7h 22m` (A14/A15) — what the time on screen would
/// actually do, kept true while the dialog is open.
///
/// Stateful only for the tick, which re-aims at each wall-clock :00 rather
/// than running `Timer.periodic` — the label has to flip when the minute does,
/// not a minute after the dialog opened. The aim itself is core's
/// [untilNextMinute], shared with Nivaat's three tickers.
///
/// **[at] is a callback, and that is not a style choice**: the target moves
/// too. Sit on the bedtime picker while the clock reaches 21:56 and "the next
/// 21:56" becomes tomorrow's; a captured `DateTime` would go past, empty the
/// line, and stay empty until you nudged something.
///
/// [at] is non-null: neither picker can draft a time that is behind them (see
/// [arunodayPickerInLabel]), so the line always has a number and the dialog
/// cannot change height under your thumb.
class _DraftCountdown extends StatefulWidget {
  const _DraftCountdown({required this.at});

  final DateTime Function() at;

  @override
  State<_DraftCountdown> createState() => _DraftCountdownState();
}

class _DraftCountdownState extends State<_DraftCountdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _arm() {
    _tick?.cancel();
    _tick = Timer(untilNextMinute(), () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  @override
  Widget build(BuildContext context) => Text(
        arunodayPickerInLabel(widget.at()),
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      );
}

class _BedtimeDialog extends StatefulWidget {
  const _BedtimeDialog({
    required this.initialOffset,
    required this.autoMinutes,
    this.wakeMinuteOfDay,
  });

  /// Signed offset from auto, −720..720 (the source of truth, like wake).
  final int initialOffset;

  /// The sleep plan's bedtime — the anchor [initialOffset] is measured from.
  final int autoMinutes;

  /// Next wake's minute-of-day — live collision cue (MESSAGES A16).
  final int? wakeMinuteOfDay;

  @override
  State<_BedtimeDialog> createState() => _BedtimeDialogState();
}

class _BedtimeDialogState extends State<_BedtimeDialog> {
  late int _offset = widget.initialOffset;

  int get _auto => widget.autoMinutes;
  int get _absolute => ((_auto + _offset) % 1440 + 1440) % 1440;

  String? get _conflict => arunodayBedtimeConflictsWithWake(
        bedtimeMinuteOfDay: _absolute,
        wakeMinuteOfDay: widget.wakeMinuteOfDay,
      );

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
    final conflict = _conflict;
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
          const SizedBox(height: 4),
          // Under the clock it describes, above the hint that explains the
          // control (Samyak, 2026-08-13). A bedtime is a clock time, so this
          // one is never empty: there is always a next time it reads 21:56.
          _DraftCountdown(
              at: () => ArunodayController.nextClockTimeAfter(
                  DateTime.now(), _absolute)),
          const SizedBox(height: 8),
          Text(
            arunodayBedtimePickerHint(widget.autoMinutes),
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
          if (conflict != null) ...[
            const SizedBox(height: 12),
            Text(
              conflict,
              style: text.bodyMedium!.copyWith(
                color: AppPalette.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed:
              conflict != null ? null : () => Navigator.pop(context, _offset),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _OffsetDialog extends StatefulWidget {
  const _OffsetDialog({
    required this.initialMinutes,
    required this.nextDawn,
    required this.draftRing,
    this.bedtimeMinuteOfDay,
  });

  final int initialMinutes;

  /// The dawn this offset is measured from — the anchor for the hint, the
  /// wake-time picker, and the collision check. Required: a picker with no
  /// anchor can't validate what it saves, so [_SettingsPageState._editOffset]
  /// declines to open one instead.
  final DateTime nextDawn;

  /// Current bedtime minute-of-day — live collision cue (MESSAGES A16).
  final int? bedtimeMinuteOfDay;

  /// When the drafted offset would next ring — the live countdown (A15).
  /// [ArunodayController.draftWakeRing].
  final DateTime? Function(int offsetMinutes) draftRing;

  @override
  State<_OffsetDialog> createState() => _OffsetDialogState();
}

class _OffsetDialogState extends State<_OffsetDialog> {
  late int _minutes = widget.initialMinutes;

  String? get _conflict => arunodayWakeConflictsWithBedtime(
        wakeOffsetMinutes: _minutes,
        dawn: widget.nextDawn,
        bedtimeMinuteOfDay: widget.bedtimeMinuteOfDay,
      );

  /// Clamped to ±12h: beyond that an "offset from dawn" loses its meaning
  /// (a day-D wake lands on day D+1 and collides with D+1's own wake).
  /// The wake-time picker naturally lands in the same range.
  void _bump(int delta) =>
      setState(() => _minutes = bumpOffset(_minutes, delta));

  /// Pick the desired wake clock time; the dawn offset is back-computed
  /// (wrapped to the nearest half-day, so 04:30 before a 05:36 dawn = −1:06).
  Future<void> _pickWakeTime() async {
    final dawnM = widget.nextDawn.hour * 60 + widget.nextDawn.minute;
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
    final conflict = _conflict;
    return AlertDialog(
      title: Text('WAKE OFFSET', style: text.labelSmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _pickWakeTime,
            child: Text(fmtOffset(_minutes), style: text.displayLarge),
          ),
          const SizedBox(height: 4),
          // The offset alone says nothing about when you'd be woken; this is
          // the line that does (Samyak, 2026-08-13). It answers for the
          // morning the drafted offset really lands on, which past a few
          // hours is not today's.
          // `!` — the window walk always finds a morning: this dialog needs a
          // location, and a location with no daily dawn is refused at add.
          _DraftCountdown(at: () => widget.draftRing(_minutes)!),
          const SizedBox(height: 8),
          Text(
            arunodayWakeOffsetHint(widget.nextDawn, _minutes),
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text('tap the offset to pick the wake time',
              style: text.bodyMedium, textAlign: TextAlign.center),
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
          if (conflict != null) ...[
            const SizedBox(height: 12),
            Text(
              conflict,
              style: text.bodyMedium!.copyWith(
                color: AppPalette.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed:
              conflict != null ? null : () => Navigator.pop(context, _minutes),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
