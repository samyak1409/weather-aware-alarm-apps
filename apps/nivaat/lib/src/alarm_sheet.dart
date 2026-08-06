import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'alarm_time_conflict.dart';
import 'controller.dart';
import 'engine.dart';

Future<void> showAlarmSheet(
  BuildContext context,
  NivaatController c, {
  required NivaatAlarm? alarm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AlarmSheet(c: c, existing: alarm),
  );
}

class _AlarmSheet extends StatefulWidget {
  const _AlarmSheet({required this.c, required this.existing});

  final NivaatController c;
  final NivaatAlarm? existing;

  @override
  State<_AlarmSheet> createState() => _AlarmSheetState();
}

class _AlarmSheetState extends State<_AlarmSheet> with WidgetsBindingObserver {
  // New alarms open on "now" (whole minutes) so the picker is already near
  // a useful time; edits keep the saved value (2026-07-22).
  late int _hour;
  late int _minute;
  // Fall back to the first court if the alarm's court was deleted — a value
  // absent from the dropdown items would assert-crash the DropdownButton.
  late String _courtId = _initialCourtId();
  // A new alarm opens on the defaults; an edit opens on what was saved, which
  // this editor is the only writer of — so both are always values the dropdown
  // and the segments actually offer.
  late int _limit =
      widget.existing?.courtSpeedLimitKmh ?? WindThresholds.defaultLimit;
  // Per-alarm retry window (30 / 60, plus a dev-gated 1), default 30.
  late int _retryMinutes =
      widget.existing?.retryMinutesAfter ?? CheckCascade.retryCapMinutesAfter;
  late final Set<int> _weekdays =
      {...(widget.existing?.weekdays ?? const {1, 2, 3, 4, 5, 6, 7})};
  // Live cue above Save — checked on open and after each time pick so
  // Save isn't the first discovery (2026-07-22).
  late String? _timeConflict;

  /// Ages the "in Xh Ym" under the clock on every wall-clock :00.
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _hour = existing.hour;
      _minute = existing.minute;
    } else {
      final now = TimeOfDay.now();
      _hour = now.hour;
      _minute = now.minute;
    }
    _timeConflict = _conflictFor(_hour, _minute);
    WidgetsBinding.instance.addObserver(this);
    _armMinuteTicker();
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Same re-aim home does. Repaint FIRST: re-arming cancels the timer that
    // came due while suspended, which would otherwise have been what redrew
    // the stale minute — without this the countdown waits for the next :00.
    if (state != AppLifecycleState.resumed) return;
    setState(() {});
    _armMinuteTicker();
  }

  /// Re-armed from the clock each hop rather than `Timer.periodic`, which
  /// counts from its own last callback and so drifts off :00 by whatever the
  /// app spent suspended — see the twin in `home_screen.dart`.
  void _armMinuteTicker() {
    _minuteTicker?.cancel();
    _minuteTicker = Timer(nivaatUntilNextMinute(), () {
      if (!mounted) return;
      setState(() {});
      _armMinuteTicker();
    });
  }

  /// Draft next ring for the live countdown — the time [_save] would arm, built
  /// from the picker's own values.
  ///
  /// The `enabled` / `ignoreEnabled` pair is deliberate (Samyak, 2026-07-26).
  /// The draft carries the real flag so it IS the alarm Save would write, and
  /// then the countdown is asked to disregard it: while you are editing a time,
  /// "in 7h 20m" is exactly the feedback you want, switched on or not. The home
  /// row stays silent for the same alarm — there the switch is the statement.
  /// (This used to fall out of the draft simply omitting `enabled`, which left
  /// `ignoreEnabled` unreachable and the behaviour accidental. It is a decision,
  /// so it now reads like one.)
  ///
  /// No [CheckState] on purpose: the draft is "if I save this clock/weekdays",
  /// not the live cascade. Mid-window continue edits may keep today's flight
  /// alive on save, but the countdown here still answers the draft time
  /// (2026-07-26, Samyak — picker feedback; home stays quiet beside Still
  /// checking). See SPEC / MESSAGES N17.
  DateTime? get _draftNextRing => nivaatNextRingAt(
        NivaatAlarm(
          id: widget.existing?.id ?? 0,
          hour: _hour,
          minute: _minute,
          courtId: _courtId,
          weekdays: _weekdays,
          enabled: widget.existing?.enabled ?? true,
        ),
        null,
        ignoreEnabled: true,
      );

  String _initialCourtId() {
    final id = widget.existing?.courtId;
    if (id != null && widget.c.courts.any((c) => c.id == id)) return id;
    return widget.c.courts.first.id;
  }

  String? _conflictFor(int hour, int minute) => nivaatAlarmTimeConflict(
        widget.c.alarms,
        NivaatAlarm(
          id: widget.existing?.id ?? widget.c.nextAlarmId(),
          hour: hour,
          minute: minute,
          courtId: _courtId,
        ),
      );

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked != null) {
      setState(() {
        _hour = picked.hour;
        _minute = picked.minute;
        _timeConflict = _conflictFor(_hour, _minute);
      });
    }
  }

  bool _saving = false;

  Future<void> _save() async {
    // Guard against double-taps: a second tap would mint a second id and
    // create a duplicate alarm.
    if (_saving || _timeConflict != null) return;
    setState(() => _saving = true);
    final alarm = NivaatAlarm(
      id: widget.existing?.id ?? widget.c.nextAlarmId(),
      hour: _hour,
      minute: _minute,
      courtId: _courtId,
      courtSpeedLimitKmh: _limit,
      retryMinutesAfter: _retryMinutes,
      weekdays: _weekdays,
      enabled: widget.existing?.enabled ?? true,
    );
    // Belt-and-suspenders — live check already disables Save; controller
    // also no-ops. Re-check here in case alarms changed while the sheet
    // was open (another path is rare but cheap).
    final conflict = nivaatAlarmTimeConflict(widget.c.alarms, alarm);
    if (conflict != null) {
      if (mounted) {
        setState(() {
          _saving = false;
          _timeConflict = conflict;
        });
      }
      return;
    }
    final saved = await widget.c.upsertAlarm(alarm);
    if (!mounted) return;
    if (!saved) {
      // Race: another alarm took this HH:MM while the sheet was open.
      setState(() {
        _saving = false;
        _timeConflict = nivaatAlarmTimeConflict(widget.c.alarms, alarm);
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final gustLimit =
        WindThresholds(courtSpeedLimitKmh: _limit).rawGustLimit;
    // Bound the sheet so large accessibility text / small phones can't
    // overflow the modal (retry row added 2026-07-26). The cap is OUTSIDE the
    // SafeArea so the status-bar / home-indicator insets come out of the 92%
    // rather than being added to it — inside, a full sheet overshot the screen.
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'NEW ALARM' : 'EDIT ALARM',
                  style: text.labelSmall),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _pickTime,
                  child: Text(
                    '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
                    style: text.displayLarge,
                  ),
                ),
              ),
              // Always built, even when blank — an empty Text still lays out a
              // full line box, so this row is exactly as tall with or without a
              // countdown. That kills a 24px jump: the label blinks out the
              // moment you deselect your last weekday, and because a bottom
              // sheet is anchored to the bottom edge, a collapsing slot doesn't
              // pull the rows below it up — it drops the 64px hero clock and
              // the title DOWN by the slot's whole height (measured). And it
              // does that WITHOUT pinning a height that large accessibility
              // text would be clipped by (at 2x the label wants 40 logical
              // pixels, not 32).
              //
              // Only the gap BELOW is mine; the gap above comes from the time
              // button's own padding. Net effect is a smaller gap above than
              // below, so the countdown reads as part of the clock rather than
              // a caption on the day chips — but the two aren't set by one pair
              // of numbers, so don't treat them as matched constants.
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Center(
                  child: Text(
                    nivaatInLabel(_draftNextRing),
                    style: text.bodyMedium,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var d = 1; d <= 7; d++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _DayChip(
                        label: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d - 1],
                        selected: _weekdays.contains(d),
                        onTap: () => setState(() {
                          if (!_weekdays.remove(d)) _weekdays.add(d);
                        }),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              // Row, not ListTile — same reason as the Keep-checking row below.
              // The old cap was a fraction of the SCREEN (0.67) while ListTile
              // divides the TILE (screen − 48 of sheet padding) and the title's
              // own width never entered the sum: "Court" + ListTile's 16 gap
              // needs ~58 in Roboto, so the row only fit on screens ≥ ~321 — and
              // at 2x text the title doubles and needs ≥ ~448, which no phone
              // has in portrait. Past that, ListTile asserts. Flex negotiates it
              // at layout time instead, so the title can be squeezed but never
              // starved, at any width or text scale (2026-07-26). 5:2 ≈ the same
              // 71/29 split the tuned 0.67 gave at normal text.
              //
              // Selected + menu both wrap (no ellipsis); `itemHeight: null` so
              // wrapped / large-accessibility lines aren't clipped at the 48px
              // default. Open menu ≤ ~1/3 screen (2026-07-22, tuned 07-23).
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    // bodyLarge explicitly: outside ListTile a bare Text
                    // inherits bodyMedium — 14px secondary grey — which
                    // quietly demoted this label below the two beside it.
                    Expanded(
                      flex: 2,
                      child: Text('Court', style: text.bodyLarge),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: LayoutBuilder(
                        builder: (context, box) => DropdownButton<String>(
                          value: _courtId,
                          isExpanded: true,
                          itemHeight: null,
                          underline: const SizedBox.shrink(),
                          menuMaxHeight:
                              MediaQuery.sizeOf(context).height * 0.33,
                          selectedItemBuilder: (context) => [
                            for (final court in widget.c.courts)
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: Text(
                                  court.name,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                          ],
                          items: [
                            for (final court in widget.c.courts)
                              DropdownMenuItem(
                                value: court.id,
                                // The menu is as wide as the button, so take
                                // the real laid-out width rather than
                                // recomputing the old screen fraction.
                                child: SizedBox(
                                  width: box.maxWidth,
                                  child: Text(court.name),
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _courtId = v!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Max wind at court'),
                subtitle: Text(
                  'Gust guard auto: ≤${gustLimit.round()} km/h',
                  style: text.bodyMedium,
                ),
                trailing: DropdownButton<int>(
                  value: _limit,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var k = WindThresholds.minLimit;
                        k <= WindThresholds.maxLimit;
                        k++)
                      DropdownMenuItem(value: k, child: Text('$k km/h')),
                  ],
                  onChanged: (v) => setState(() => _limit = v!),
                ),
              ),
              // Row (not ListTile): a 3×52 trailing overflows ListTile's
              // title slot on narrow phones; same row so 2 options later
              // still read as a trailer, not a lonely full-width bar.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // bodyLarge, not titleMedium: same 16/w400, but
                        // letter-spacing 0.5 vs 0.1, so this read subtly
                        // tighter than its neighbours. All three row labels
                        // land on bodyLarge — "Max wind at court" gets it from
                        // ListTile, Court and this one say so explicitly
                        // (locked by alarm_sheet_layout_test).
                        Text('Keep checking', style: text.bodyLarge),
                        const SizedBox(height: 2),
                        // Says the PAYOFF, which the old "After a skip,
                        // re-check for calm this long." never did — nothing
                        // told you the alarm actually rings when it clears, so
                        // there was no reason to prefer 60m over 30m. ("Skip"
                        // is also a word this screen never uses.)
                        Text(
                          'Rings late if the wind drops in time.',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _RetrySegmented(
                    value: _retryMinutes,
                    onChanged: (v) => setState(() => _retryMinutes = v),
                  ),
                ],
              ),
              if (_timeConflict != null) ...[
                const SizedBox(height: 12),
                Text(
                  _timeConflict!,
                  style: text.bodyMedium!.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.existing != null)
                    TextButton(
                      onPressed: () async {
                        await widget.c.deleteAlarm(widget.existing!.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Delete',
                          style: TextStyle(color: AppPalette.textSecondary)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _weekdays.isEmpty ||
                            _saving ||
                            _timeConflict != null
                        ? null
                        : _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact trailing segments — 30 / 60 min, plus a dev-only 1m — in the
/// day-chip accent language. Width tracks option count, so the control is a
/// trailer at either size.
class _RetrySegmented extends StatelessWidget {
  const _RetrySegmented({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  /// Listens rather than reads: the gate is seven taps away on the home
  /// screen, so it cannot flip while this sheet is up — but a widget that
  /// silently depends on a notifier it never subscribes to is a bug waiting
  /// for the day something else can flip it.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DevMode.enabled,
      builder: (context, devMode, _) => _control(
        context,
        CheckCascade.retryOptionsFor(devMode: devMode, selected: value),
      ),
    );
  }

  Widget _control(BuildContext context, List<int> options) {
    // "60m" is three glyphs in a box the size of a one-glyph day chip, so this
    // is the tightest text in the sheet: measured, it starts clipping just past
    // 1.3x and loses half the label at 2x — and the ClipRRect below hides that
    // as a silent crop instead of an overflow stripe. Compact segmented
    // controls clamp their own scaling (iOS does the same); the label and hint
    // beside it still scale all the way, so nothing becomes unreadable. The box
    // grows by the SAME clamped factor, so the fit holds at every scale.
    final f = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: options.length * 52 * f,
          height: 36 * f,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  if (i > 0)
                    Container(width: 1, color: AppPalette.hairline),
                  Expanded(
                    child: _RetrySegment(
                      minutes: options[i],
                      selected: value == options[i],
                      onTap: () => onChanged(options[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RetrySegment extends StatelessWidget {
  const _RetrySegment({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Compact trailing labels — "30m" / "60m", and "1m" behind the gate.
    final label = '${minutes}m';
    return Material(
      color: selected ? AppPalette.wind : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Center(
          // Same type as _DayChip two rows up — selection reads from the wind
          // fill and the black-on-accent text, never from extra weight (the
          // quiet styles stay w400 in both type modes; see CLAUDE.md).
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? AppPalette.trueBlack : AppPalette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppPalette.wind : Colors.transparent,
          border: Border.all(
            color: selected ? AppPalette.wind : AppPalette.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AppPalette.trueBlack : AppPalette.textSecondary,
          ),
        ),
      ),
    );
  }
}
