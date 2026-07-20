import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

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
    return Padding(
      padding: widget.padding,
      child: Center(
        child: Text.rich(
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
    );
  }
}
