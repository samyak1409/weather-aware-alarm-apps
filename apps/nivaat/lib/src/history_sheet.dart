import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'engine.dart';

void showHistorySheet(BuildContext context, NivaatController c) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HistorySheet(c: c),
  );
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.c});

  final NivaatController c;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

/// Listens to the controller, like the settings page does. Without
/// it a background check that lands a row while this sheet is open showed up
/// only after closing and reopening — home and the settings row count were
/// already live, so the open log was the one stale surface (2026-07-26).
class _HistorySheetState extends State<_HistorySheet> {
  NivaatController get c => widget.c;

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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SizedBox(
        // Fixed height, accepted 2026-07-22: rows grow under large
        // accessibility text and this box doesn't. Reviewed and left as-is —
        // don't "fix" it into an intrinsic/fractional height without asking.
        height: 480,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HISTORY', style: text.labelSmall),
              const SizedBox(height: 8),
              if (c.history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Every ring and skip lands here, with the wind that caused it.',
                    style: text.bodyMedium,
                  ),
                ),
              Expanded(
                // Same "there's more below" flash-on-open cue as the courts
                // sheet and the settings pages (added 2026-07-20).
                child: FlashingScrollbar(
                  builder: (scroll) => ListView.separated(
                    controller: scroll,
                    itemCount: c.history.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final h = c.history[i];
                      // A cancelled row keeps the last known wind reason in
                      // its data but shows none of it, so it needs its own
                      // icon too — the wind isn't what ended that occurrence.
                      final icon = h.kind == HistoryKind.cancelled
                          ? Icons.cancel_outlined
                          : switch (h.ringDisposition) {
                              RingDisposition.missed ||
                              RingDisposition.unknown =>
                                Icons.alarm_off_outlined,
                              _ => switch (h.outcome) {
                                  CheckOutcome.rang =>
                                    Icons.notifications_active_outlined,
                                  CheckOutcome.skippedWindy ||
                                  CheckOutcome.skippedGusty =>
                                    Icons.air,
                                  CheckOutcome.skippedNoData =>
                                    Icons.cloud_off_outlined,
                                },
                            };
                      // Both lines are built outside this widget, so they can
                      // be asserted as whole strings — see nivaatHistorySub.
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(icon, size: 20),
                        title: Text(nivaatHistoryLine(h),
                            style: text.titleMedium),
                        subtitle: Text(
                          // `!` — every load prunes rows whose court is gone.
                          nivaatHistorySub(h, c.courtById(h.courtId)!.name),
                          style: text.bodyMedium,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
