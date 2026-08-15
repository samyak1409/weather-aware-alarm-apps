/// The furniture both settings pages are made of (2026-08-15).
///
/// Extracted because the two pages drifted apart on exactly this furniture
/// twice in one day — a section break 4pt tighter than its siblings, banners
/// 8pt apart — each caught by eye and then pinned by a test that greps both
/// files for the same literal. That works, but only ever after the drift is
/// written. One copy makes it unrepresentable, which is why
/// `spacing_parity_test` no longer asserts the gutter, the break or the
/// empty-section pad; it checks both pages still use these instead.
library;

import 'package:flutter/material.dart';

import 'crafted_by.dart';
import 'flashing_scrollbar.dart';
import 'models.dart';
import 'place_info_button.dart';
import 'theme.dart';

/// The page shell: `SETTINGS` bar, one scrolling surface, pinned maker's mark.
///
/// **The mark stays outside the scrollable** — inside the list it walks off the
/// bottom once there are enough saved places, taking the seven-tap developer
/// gate with it. Its 20pt top pad is the other half: mid-scroll rows sit flush
/// at the scroll area's bottom edge and would otherwise kiss it (the list's own
/// bottom padding cannot do this — that only exists at the END of the list).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.accent,
    required this.children,
  });

  /// The app's accent — the maker's mark's heart, and its toast.
  final Color accent;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('SETTINGS', style: text.labelSmall)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              // The whole page scrolls as ONE surface (2026-07-20) — no inner
              // scroll regions. `FlashingScrollbar` adds the
              // flash-on-open-if-overflowing cue.
              child: FlashingScrollbar(
                builder: (scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: children,
                ),
              ),
            ),
            CraftedBy(
              accent: accent,
              padding: const EdgeInsets.only(top: 20, bottom: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section break and its label: the `4 / rule / 8` rhythm, the `labelSmall`
/// heading, an optional `+`, and an optional line for when the section is
/// empty.
///
/// One widget rather than four loose children, so a page cannot grow a break
/// with a different rhythm — which is precisely what had happened.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.label,
    this.onAdd,
    this.emptyNote,
  });

  /// ALL-CAPS, e.g. `APPEARANCE` / `LOCATIONS` / `COURTS`.
  final String label;

  /// A `+` beside the heading, or null for a section you cannot add to.
  final VoidCallback? onAdd;

  /// Shown under the heading when the section has nothing in it — the state
  /// neither app could reach until settings opened without a saved place.
  final String? emptyNote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final note = emptyNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(label, style: text.labelSmall),
            if (onAdd != null) ...[
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                color: AppPalette.textSecondary,
                onPressed: onAdd,
              ),
            ],
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(note, style: text.bodyMedium),
          ),
      ],
    );
  }
}

/// The trailing pair on a saved-place row: where it came from, then the bin.
///
/// Both apps' rows differ above this — Arunoday leads with an active-location
/// radio, Nivaat subtitles with coordinates — but the two controls on the
/// right are the same two controls, and a place row that grew a third button
/// in one app only is the drift this exists to prevent.
class PlaceRowActions extends StatelessWidget {
  const PlaceRowActions({
    super.key,
    required this.place,
    required this.accent,
    required this.onDelete,
  });

  final SavedLocation place;
  final Color accent;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlaceInfoButton(place: place, accent: accent),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          color: AppPalette.textSecondary,
          onPressed: onDelete,
        ),
      ],
    );
  }
}
