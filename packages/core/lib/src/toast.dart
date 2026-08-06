import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// How long a toast stays up before it fades out.
const Duration _kToastDuration = Duration(seconds: 2);

/// Gap between the pill and the bottom safe area, used only when no [centerY]
/// is given. Flutter's own floating-snackbar offset, measured.
const double _kToastBottomGap = 10;

/// The toast on screen, if any. One at a time: a second message replaces the
/// first rather than queueing behind it, since by then the first is stale news.
OverlayEntry? _current;

/// Shows [message] as a small pill in [accent] — centred on [centerY] when
/// given, otherwise just above the bottom safe area.
///
/// **An overlay rather than a `SnackBar`, and that is the whole reason this
/// exists (2026-08-06, Samyak).** A floating snackbar is positioned by the
/// Scaffold, which lifts it to clear the FloatingActionButton
/// (`scaffold.dart`: `snackBarYOffsetBase = floatingActionButtonRect.top`) —
/// so one call landed at the foot of Arunoday's home and 72pt higher up
/// Nivaat's (measured), and nothing on the SnackBar can move it back down: `margin` only
/// ever raises it further, and `width` is horizontal. One gesture has to
/// answer in one place in both apps.
///
/// It also **sizes to its text**, which a snackbar cannot: that one stretches
/// to fill whatever width it is given, leaving slack either side of a short
/// message. Long text wraps within the screen rather than widening.
///
/// [centerY] is a screen y-coordinate to centre the pill on — pass the middle
/// of whatever the toast is answering for and it lands squarely over it, which
/// is what makes it read as that thing's reply rather than as a bar that
/// happened to appear (Samyak, 2026-08-06: the maker's mark). Without it the
/// pill sits just above the bottom safe area.
void showAppToast(
  BuildContext context,
  String message, {
  required Color accent,
  double? centerY,
}) {
  final overlay = Overlay.maybeOf(context);
  // No overlay means nothing to float over. Never worth surfacing: whatever
  // the caller did has already happened, and the toast only reports it.
  if (overlay == null) return;
  _current?.remove();
  _current = null;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _ToastPill(
      message: message,
      accent: accent,
      centerY: centerY,
      // Guarded, because a replacement already removed this entry and an
      // OverlayEntry may not be removed twice.
      onFinished: () {
        if (!identical(_current, entry)) return;
        entry.remove();
        _current = null;
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

class _ToastPill extends StatefulWidget {
  const _ToastPill({
    required this.message,
    required this.accent,
    required this.centerY,
    required this.onFinished,
  });

  final String message;
  final Color accent;
  final double? centerY;
  final VoidCallback onFinished;

  @override
  State<_ToastPill> createState() => _ToastPillState();
}

class _ToastPillState extends State<_ToastPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  /// Held so [dispose] can cancel it — a timer still pending when the tree
  /// goes is a leak in the app and a test failure in the suite.
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _fade.forward();
    _hold = Timer(_kToastDuration, _leave);
  }

  Future<void> _leave() async {
    try {
      await _fade.reverse();
    } on TickerCanceled {
      // Disposed mid-fade: the entry is already gone.
      return;
    }
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centerY = widget.centerY;
    return Positioned(
      // The inset IS the width cap: Align shrink-wraps the pill inside it, so
      // a short message is its own width and a long one wraps here.
      left: 24,
      right: 24,
      // Anchored by its own MIDDLE when there is something to centre on. The
      // pill's height isn't known until it has laid out, so `top` puts its top
      // edge on the anchor and FractionalTranslation lifts it back by half of
      // whatever it turned out to be — no measuring pass, no guessed height.
      top: centerY,
      bottom: centerY == null
          ? MediaQuery.viewPaddingOf(context).bottom + _kToastBottomGap
          : null,
      // Never takes a touch. It is centred ON what it answers for, so without
      // this its Material swallowed the next taps on the very thing that
      // raised it — seven more taps on the mark did nothing until it faded.
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: Offset(0, centerY == null ? 0 : -0.5),
          child: FadeTransition(
            opacity: _fade,
            // heightFactor, because anchoring by `top` leaves the height
            // unbounded and Align has to take the pill's own.
            child: Align(
              heightFactor: 1,
              child: Material(
                // The elevated grey every other overlay uses (theme.dart),
                // with the app's accent — the colour of what you tapped.
                color: AppPalette.surface,
                shape: const StadiumBorder(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: widget.accent),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
