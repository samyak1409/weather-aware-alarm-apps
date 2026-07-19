import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';

/// Returns true if at least one court exists when the sheet closes.
Future<bool> showCourtsSheet(
  BuildContext context,
  NivaatController c, {
  bool promptAdd = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CourtsSheet(c: c, promptAdd: promptAdd),
  );
  return c.courts.isNotEmpty;
}

class _CourtsSheet extends StatefulWidget {
  const _CourtsSheet({required this.c, required this.promptAdd});

  final NivaatController c;
  final bool promptAdd;

  @override
  State<_CourtsSheet> createState() => _CourtsSheetState();
}

class _CourtsSheetState extends State<_CourtsSheet> {
  NivaatController get c => widget.c;
  final _scroll = ScrollController();
  bool _flashScrollbar = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.promptAdd && c.courts.isEmpty) {
        _addCourt();
      } else {
        _maybeFlashScrollbar();
      }
    });
  }

  void _maybeFlashScrollbar() {
    if (!mounted ||
        !_scroll.hasClients ||
        _scroll.position.maxScrollExtent <= 0) {
      return;
    }
    setState(() => _flashScrollbar = true);
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _flashScrollbar = false);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Warns what deleting [name] takes with it: its alarms and its history log
  /// (both are removed). History only exists once an alarm has fired at least
  /// once, so a fresh court names just its alarms.
  String _deleteWarning(String name, int alarms, int history) {
    final a = '$alarms alarm${alarms == 1 ? '' : 's'}';
    final h = '$history history ${history == 1 ? 'entry' : 'entries'}';
    if (alarms > 0 && history > 0) {
      return '$a use $name and will be deleted too, along with $h. Continue?';
    }
    if (alarms > 0) {
      return '$a use $name and will be deleted too. Continue?';
    }
    return '$h for $name will be deleted too. Continue?';
  }

  Future<void> _deleteCourt(SavedLocation court) async {
    final n = c.alarmsForCourt(court.id);
    final h = c.historyForCourt(court.id);
    if (n > 0 || h > 0) {
      final text = Theme.of(context).textTheme;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('DELETE COURT', style: text.labelSmall),
          content: Text(_deleteWarning(court.name, n, h)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await c.removeCourt(court.id);
  }

  Future<void> _addCourt() async {
    final place = await showLocationSearch(context, validate: (lat, lon) {
      final dup = c.existingCourtNear(lat, lon);
      return dup == null ? null : 'Same spot as ${dup.name} — already added.';
    });
    if (place == null || !mounted) return;
    await c.addCourt(place);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('COURTS', style: text.labelSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  color: AppPalette.textSecondary,
                  onPressed: _addCourt,
                ),
              ],
            ),
            if (c.courts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Save your courts — each alarm checks the wind at its own court.',
                  style: text.bodyMedium,
                ),
              ),
            // Bound + scroll the list so many courts don't overflow the sheet;
            // scrollbar fades in on scroll and flashes once on open.
            if (c.courts.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: _flashScrollbar ? true : null,
                  child: ListView(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(right: 8),
                    children: [
                      for (final court in c.courts)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(court.name),
                          subtitle: Text(
                            '${court.lat.toStringAsFixed(3)}, '
                            '${court.lon.toStringAsFixed(3)}',
                            style: text.bodyMedium,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            color: AppPalette.textSecondary,
                            onPressed: () => _deleteCourt(court),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
