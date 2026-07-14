import 'package:core/core.dart';
import 'package:flutter/material.dart';

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
  late int _hour = widget.existing?.hour ?? 6;
  late int _minute = widget.existing?.minute ?? 0;
  // Fall back to the first court if the alarm's court was deleted — a value
  // absent from the dropdown items would assert-crash the DropdownButton.
  late String _courtId = _initialCourtId();

  String _initialCourtId() {
    final id = widget.existing?.courtId;
    if (id != null && widget.c.courts.any((c) => c.id == id)) return id;
    return widget.c.courts.first.id;
  }
  late int _limit =
      widget.existing?.courtSpeedLimitKmh ?? WindThresholds.defaultLimit;
  late final Set<int> _weekdays =
      {...(widget.existing?.weekdays ?? const {1, 2, 3, 4, 5, 6, 7})};

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked != null) {
      setState(() {
        _hour = picked.hour;
        _minute = picked.minute;
      });
    }
  }

  bool _saving = false;

  Future<void> _save() async {
    // Guard against double-taps: a second tap would mint a second id and
    // create a duplicate alarm.
    if (_saving) return;
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
    await widget.c.upsertAlarm(alarm);
    if (mounted) Navigator.pop(context);
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Court'),
              trailing: DropdownButton<String>(
                value: _courtId,
                underline: const SizedBox.shrink(),
                items: [
                  for (final court in widget.c.courts)
                    DropdownMenuItem(
                      value: court.id,
                      child: Text(court.name),
                    ),
                ],
                onChanged: (v) => setState(() => _courtId = v!),
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
                  onPressed: _weekdays.isEmpty || _saving ? null : _save,
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
