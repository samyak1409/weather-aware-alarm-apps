import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';
import 'toast.dart';

/// The ⓘ on a saved place's row, in both apps (2026-08-15, Samyak).
///
/// A saved place shows only the name you kept — which is the point, since you
/// named it — and that leaves no way to tell two `Home`s apart, or to remember
/// whether the coordinates came off the map or off the phone. Tapping this says
/// so: the geocoder's full place for a searched one, `Saved using GPS` for a
/// fix. [savedLocationDetail] is the whole sentence, so it is asserted where
/// every other string is.
///
/// **A toast rather than a dialog**, and the same one the maker's-mark gesture
/// uses (X8): a dialog for one line of read-only text is a second tap to get
/// rid of, and the pill is already sized to its text and pointer-transparent.
/// It is centred on this button's own middle — the row's middle, since they
/// share a baseline — so it reads as that row's answer rather than as a bar
/// that happened to appear.
class PlaceInfoButton extends StatelessWidget {
  const PlaceInfoButton({
    super.key,
    required this.place,
    required this.accent,
  });

  final SavedLocation place;

  /// The app's accent — the toast is drawn in the colour of what you tapped.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 20),
      color: AppPalette.textSecondary,
      tooltip: 'Where this place came from',
      onPressed: () {
        // The button's own box, read at tap time: the row it sits in may have
        // scrolled since it was built, and a stale y would park the pill over
        // a different place's row. Not null-guarded — a tap means this button
        // is on screen and laid out.
        final box = context.findRenderObject()! as RenderBox;
        showAppToast(
          context,
          savedLocationDetail(place),
          accent: accent,
          centerY: box.localToGlobal(box.size.center(Offset.zero)).dy,
        );
      },
    );
  }
}
