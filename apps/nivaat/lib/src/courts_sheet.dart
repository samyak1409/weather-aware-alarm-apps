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

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    if (widget.promptAdd && c.courts.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addCourt());
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addCourt() async {
    final place = await showLocationSearch(context);
    if (place != null) await c.addCourt(place);
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
            ...c.courts.map(
              (court) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(court.name),
                subtitle: Text(
                  '${court.lat.toStringAsFixed(3)}, ${court.lon.toStringAsFixed(3)}',
                  style: text.bodyMedium,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: AppPalette.textSecondary,
                  onPressed: () => c.removeCourt(court.id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
