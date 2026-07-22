import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'alarm_time_conflict.dart';
import 'controller.dart';

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

class _AlarmSheetState extends State<_AlarmSheet> {
  // New alarms open on "now" (whole minutes) so the picker is already near
  // a useful time; edits keep the saved value (2026-07-22).
  late int _hour;
  late int _minute;
  // Fall back to the first court if the alarm's court was deleted — a value
  // absent from the dropdown items would assert-crash the DropdownButton.
  late String _courtId = _initialCourtId();
  // Clamp defensively so an out-of-range saved value never crashes the dropdown.
  late int _limit =
      (widget.existing?.courtSpeedLimitKmh ?? WindThresholds.defaultLimit)
          .clamp(WindThresholds.minLimit, WindThresholds.maxLimit);
  late final Set<int> _weekdays =
      {...(widget.existing?.weekdays ?? const {1, 2, 3, 4, 5, 6, 7})};
  // Live cue above Save — checked on open and after each time pick so
  // Save isn't the first discovery (2026-07-22).
  late String? _timeConflict;

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
  }

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

    return SafeArea(
      child: Padding(
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
            const SizedBox(height: 8),
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
            Builder(builder: (context) {
              // Cap trailing width so a long court name can't crush "Court"
              // into one-char-per-line (2026-07-22). Selected + menu both
              // wrap (no ellipsis — 2026-07-23); `itemHeight: null` so wrapped
              // / large-accessibility lines aren't clipped at the 48px default.
              // Menu height capped at half screen.
              final halfW = MediaQuery.sizeOf(context).width * 0.5;
              final halfH = MediaQuery.sizeOf(context).height * 0.5;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Court'),
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: halfW),
                  child: DropdownButton<String>(
                    value: _courtId,
                    isExpanded: true,
                    itemHeight: null,
                    underline: const SizedBox.shrink(),
                    menuMaxHeight: halfH,
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
                          child: SizedBox(
                            width: halfW,
                            child: Text(court.name),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _courtId = v!),
                  ),
                ),
              );
            }),
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
            if (_timeConflict != null) ...[
              const SizedBox(height: 8),
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
