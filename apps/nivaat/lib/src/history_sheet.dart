import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';

void showHistorySheet(BuildContext context, NivaatController c) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HistorySheet(c: c),
  );
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.c});

  final NivaatController c;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SizedBox(
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
                child: ListView.separated(
                  itemCount: c.history.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final h = c.history[i];
                    final (icon, line) = switch (h.outcome) {
                      CheckOutcome.rang => (
                          Icons.notifications_active_outlined,
                          'Rang ${(h.volume! * 100).round()}% · ${h.windGustSummary}'
                        ),
                      CheckOutcome.skippedWindy => (
                          Icons.air,
                          'Skipped (windy) · ${h.windGustSummary}'
                        ),
                      CheckOutcome.skippedGusty => (
                          Icons.air,
                          'Skipped (gusty) · ${h.windGustSummary}'
                        ),
                      CheckOutcome.skippedNoData => (
                          Icons.cloud_off_outlined,
                          'Skipped · could not check the wind'
                        ),
                    };
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon, size: 20),
                      title: Text(line, style: text.titleMedium),
                      subtitle: Text(
                        '${fmtShortDate(h.at)} · ${fmtClock(h.at)}',
                        style: text.bodyMedium,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
