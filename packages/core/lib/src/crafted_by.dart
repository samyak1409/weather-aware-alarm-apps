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
/// flip the hidden switch and say which way it went — SAMYAK's own taps
/// included, which is why the link waits before it opens ([linkDelay]).
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

  /// How long a tap on SAMYAK waits before the site opens.
  ///
  /// **The link is held rather than followed straight away** (2026-08-20,
  /// Samyak). SAMYAK is the widest target on the mark, so it is where a thumb
  /// going for the seven-tap gate lands — and it used to answer every one of
  /// those taps with a browser, seven times over, while the run it should have
  /// been counting never moved. A tap now waits out one run window: another
  /// tap inside it cancels the visit and carries the run on, so the same seven
  /// taps flip [DevMode] wherever on the mark they fall.
  ///
  /// **Only the FIRST tap of a run ever arms it** (Samyak, 2026-08-20). A
  /// second tap is already someone going for the gate, and giving up at three
  /// does not turn those three back into a link tap — it opens a browser over
  /// a gesture that was abandoned, which is the annoyance this whole delay
  /// exists to remove. So a run that stalls short of seven opens nothing at
  /// all, and a lone tap is the only tap that reaches the site. **An unlock
  /// does not end the run**, so the eighth tap of one is not a first tap
  /// either — [DevTapRun] puts its count back to 1 on a pause and on nothing
  /// else, which is what keeps `taps == 1` meaning what it says.
  ///
  /// [DevMode.tapGap] plus a millisecond, because a tap at exactly the gap
  /// still continues the run (see [DevTapRun.tap]) — waiting the gap itself
  /// would leave the last tap of a run racing the browser.
  static final Duration linkDelay =
      DevMode.tapGap + const Duration(milliseconds: 1);

  @override
  State<CraftedBy> createState() => _CraftedByState();
}

class _CraftedByState extends State<CraftedBy> {
  late final TapGestureRecognizer _onName = TapGestureRecognizer()
    ..onTap = () => _tapMark(onName: true);

  final DevTapRun _devTaps = DevTapRun();

  /// A tap on SAMYAK that has not opened the site yet — see [linkDelay].
  Timer? _pendingSite;

  /// On the mark's own line, so its middle can be measured rather than
  /// guessed. The widget's box is not the same thing — it carries [padding].
  final GlobalKey _markLine = GlobalKey();

  /// Where the middle of the mark is on screen.
  ///
  /// Only ever read from [_tapMark], and a tap means the line is on screen and
  /// laid out — so the box and its size both exist by then. The null-and-
  /// `hasSize` guard this used to carry was defence against a state a tap
  /// handler cannot be in (Samyak, 2026-08-15).
  double get _markCenterY {
    final box = _markLine.currentContext!.findRenderObject()! as RenderBox;
    return box.localToGlobal(box.size.center(Offset.zero)).dy;
  }

  /// One tap anywhere on the mark; seven of them flip [DevMode] and announce
  /// it. [onName] is a tap on SAMYAK, which owes the site a visit if it is
  /// the only tap in its run — see [CraftedBy.linkDelay].
  void _tapMark({bool onName = false}) {
    // Any tap on the mark answers a waiting one, SAMYAK or not: it is all one
    // run, so it is all the same evidence that they are still tapping.
    _pendingSite?.cancel();
    _pendingSite = null;
    if (!_devTaps.tap(DateTime.now())) {
      // `taps == 1` is what makes this a LINK tap rather than the start of a
      // gesture; past one — an unlock included, since only a pause resets the
      // count — they are going for the gate, and the site is not what they
      // asked for however the run ends.
      if (onName && _devTaps.taps == 1) {
        _pendingSite = Timer(CraftedBy.linkDelay, _openSite);
      }
      return;
    }
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

  void _openSite() => unawaited((widget.openSite ?? _launch)());

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
    _pendingSite?.cancel();
    _onName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelSmall!;
    return GestureDetector(
      // The whole padded footer, because the heart alone is 11px of one 10px
      // line — `opaque` over padding that was already there, so nothing moves.
      // SAMYAK still wins its own taps — its RenderParagraph sits deeper, so
      // it enters the gesture arena first and this detector never sees them.
      // That is why its recognizer calls [_tapMark] itself rather than just
      // opening the site: the run has to count them too (locked by
      // dev_mode_test).
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
