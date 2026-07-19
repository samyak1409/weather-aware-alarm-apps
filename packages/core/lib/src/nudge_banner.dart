import 'package:flutter/material.dart';

import 'theme.dart';

/// The shared look of a home-screen nudge: a bordered surface card with a
/// plain-words problem statement and one accent-colored action. Every nudge
/// (denied alarms, denied notifications, throttled background work) renders
/// through this so they all read the same.
class NudgeBanner extends StatelessWidget {
  const NudgeBanner({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.accent,
    this.margin = const EdgeInsets.fromLTRB(28, 0, 28, 12),
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  /// The app's accent (`AppPalette.dawn` / `.wind`) for the action.
  final Color accent;

  /// Outer margin. Defaults to 28-inset for screens whose column isn't already
  /// padded; pass a no-horizontal margin where the parent already insets.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: text.bodyMedium!.copyWith(color: AppPalette.textPrimary),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: text.labelSmall!.copyWith(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}
