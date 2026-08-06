import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dev_mode.dart';
import 'theme.dart';
import 'toast.dart';

/// Samyak's site — tapping his name in the mark opens it (2026-07-20).
const String craftedBySiteUrl = 'https://samyak1409.github.io';

/// "CRAFTED WITH ♥ BY SAMYAK" — the maker's mark at the foot of both home
/// screens (2026-07-20, Samyak). Speaks the apps' small-caps label idiom
/// (ARUNODAY, WAKE · DAWN) so it reads as part of the design, not a sticker.
///
/// The heart is [Icons.favorite], not a heart character: Android's font
/// fallback promotes text hearts to the color emoji (baked-in red, ignores
/// the palette — device-caught 2026-07-20) while iOS keeps the glyph; the
/// icon font renders identically on both and takes the app's accent.
///
/// **It is also the way into [DevMode]** (2026-08-06): seven taps on the mark
/// flip the hidden switch and say which way it went.
class CraftedBy extends StatefulWidget {
  const CraftedBy({
    super.key,
    required this.accent,
    this.padding = const EdgeInsets.only(bottom: 10),
    this.openSite,
  });

  /// The app's accent ([AppPalette.dawn] / [AppPalette.wind]) — the heart.
  final Color accent;

  final EdgeInsetsGeometry padding;

  /// Test seam; defaults to opening [craftedBySiteUrl] in the browser.
  final Future<void> Function()? openSite;

  @override
  State<CraftedBy> createState() => _CraftedByState();
}

class _CraftedByState extends State<CraftedBy> {
  late final TapGestureRecognizer _onName = TapGestureRecognizer()
    ..onTap = () => unawaited((widget.openSite ?? _launch)());

  final DevTapRun _devTaps = DevTapRun();

  /// On the mark's own line, so its middle can be measured rather than
  /// guessed. The widget's box is not the same thing — it carries [padding].
  final GlobalKey _markLine = GlobalKey();

  /// Where the middle of the mark is on screen, or null before it has laid
  /// out (nothing can be tapped before then, so this is defence only).
  double? get _markCenterY {
    final box = _markLine.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero)).dy;
  }

  /// Seven of these flip [DevMode] and announce it.
  void _tapMark() {
    if (!_devTaps.tap(DateTime.now())) return;
    final on = !DevMode.enabled.value;
    unawaited(DevMode.setEnabled(on));
    // Centred ON the mark, not floating above it (Samyak, 2026-08-06): the
    // toast is the mark's answer, and landing squarely over the line you just
    // tapped is what makes it read that way. See `showAppToast` for why this
    // is not a SnackBar — one lands in a different place in each app.
    showAppToast(
      context,
      on ? kDevModeOnMessage : kDevModeOffMessage,
      accent: widget.accent,
      centerY: _markCenterY,
    );
  }

  static Future<void> _launch() async {
    try {
      await launchUrl(
        Uri.parse(craftedBySiteUrl),
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      // No browser / launcher refused — the mark is decoration, stay quiet.
    }
  }

  @override
  void dispose() {
    _onName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelSmall!;
    return GestureDetector(
      // The whole padded footer, because the heart alone is 11px of one 10px
      // line — `opaque` over padding that was already there, so nothing moves.
      // SAMYAK still wins its own taps: its RenderParagraph sits deeper, so it
      // enters the gesture arena first and opening the site never counts
      // towards the run (locked by dev_mode_test).
      behavior: HitTestBehavior.opaque,
      onTap: _tapMark,
      child: Padding(
        padding: widget.padding,
        child: Center(
          child: Text.rich(
            key: _markLine,
            TextSpan(
              children: [
                const TextSpan(text: 'CRAFTED WITH '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.favorite, size: 11, color: widget.accent),
                ),
                const TextSpan(text: ' BY '),
                TextSpan(text: 'SAMYAK', recognizer: _onName),
              ],
            ),
            style: label.copyWith(fontSize: 10),
          ),
        ),
      ),
    );
  }
}
