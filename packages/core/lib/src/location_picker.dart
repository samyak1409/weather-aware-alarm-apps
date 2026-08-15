import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'models.dart';
import 'open_meteo.dart';
import 'theme.dart';

/// Inline message for geocode [Exception]s; `null` for programming [Error]s.
@visibleForTesting
String? locationSearchErrorMessage(Object error) =>
    error is Exception ? 'Search failed — check network' : null;

/// Shows the network message for [Exception]s; rethrows programming [Error]s
/// so bugs are never disguised as "check network".
@visibleForTesting
void reportLocationSearchFailure(
  Object error,
  void Function(String message) show, {
  StackTrace? stackTrace,
}) {
  final msg = locationSearchErrorMessage(error);
  if (msg == null) {
    if (stackTrace != null) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    // ignore: only_throw_errors — intentional rethrow of non-Exception
    throw error;
  }
  show(msg);
}

/// Shared bottom-sheet place picker: GPS ("use my current location", works
/// fully offline — GPS is satellite-based) or Open-Meteo geocoding search
/// (for places you aren't standing at). Returns the picked [GeoPlace], or
/// null if dismissed.
/// [validate] runs on the picked coords **before** the user is asked to name
/// a GPS spot or a search result is returned — returning a message rejects it
/// in place (shown inline), so a doomed pick never wastes the user's effort.
Future<GeoPlace?> showLocationSearch(
  BuildContext context, {
  String? Function(double lat, double lon)? validate,
}) {
  return showModalBottomSheet<GeoPlace>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LocationSearchSheet(validate: validate),
  );
}

/// Opens the place-search sheet with an injectable [OpenMeteo] — for widget
/// tests (same route as production).
@visibleForTesting
Future<GeoPlace?> showLocationSearchForTest(
  BuildContext context, {
  required OpenMeteo api,
  String? Function(double lat, double lon)? validate,
}) {
  return showModalBottomSheet<GeoPlace>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LocationSearchSheet(validate: validate, api: api),
  );
}

class _LocationSearchSheet extends StatefulWidget {
  _LocationSearchSheet({this.validate, OpenMeteo? api})
      : api = api ?? OpenMeteo();

  final String? Function(double lat, double lon)? validate;
  final OpenMeteo api;

  @override
  State<_LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<_LocationSearchSheet> {
  Timer? _debounce;
  List<GeoPlace> _results = const [];
  bool _loading = false;
  bool _locating = false;
  String? _error;

  /// Which search the sheet is showing, counted up on every keystroke that
  /// changes what is being asked (REVIEW #17). The debounce cancels a pending
  /// *timer*, never a request already sent, and nothing tied a reply to the
  /// query that asked for it — a slow `To` could land after a fast `Tokyo`.
  /// Every reply checks it is still the newest before touching the screen.
  int _queryEpoch = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    // Bumped BEFORE the early return too: clearing the field must also orphan
    // whatever is in flight, or deleting your query repopulates the list.
    final epoch = ++_queryEpoch;
    if (q.trim().length < 2) {
      // `_loading` too: the request this orphans will skip its own `finally`,
      // and the bar would spin with nothing behind it.
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final results = await widget.api.geocode(q.trim());
        if (mounted && epoch == _queryEpoch) setState(() => _results = results);
      } catch (e, st) {
        reportLocationSearchFailure(
          e,
          (msg) {
            // A stale query's failure is not this query's failure — showing it
            // would put "check network" over results that arrived fine.
            if (mounted && epoch == _queryEpoch) setState(() => _error = msg);
          },
          stackTrace: st,
        );
      } finally {
        if (mounted && epoch == _queryEpoch) setState(() => _loading = false);
      }
    });
  }

  /// A **live** fix for "use my current location", or null.
  ///
  /// **There is no last-known-position fallback, and there must not be one**
  /// (REVIEW #18 · #19, Samyak 2026-08-05). `getLastKnownPosition` used to
  /// stand in whenever the 20-second fix failed — an ordinary indoor outcome —
  /// and whatever the OS still held went through `validate` and into a saved
  /// place unexamined, which is how yesterday's city becomes "Home Court".
  /// **An age limit is not the answer either**: a cached fix is a guess about
  /// where you are whatever its timestamp says, and this coordinate is saved
  /// once and then trusted by every alarm it feeds.
  ///
  /// **Null is a complete answer** — [_useGps] turns it into "try search
  /// instead" — so the one guard below covers every plugin call here. The old
  /// fallback had none of its own, sitting inside the timeout's handler, so a
  /// throw there escaped `_useGps` (a `finally`, no `catch`) with no message.
  Future<Position?> _gpsFix() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error = 'Turn on location services first');
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission denied');
        return null;
      }
      // Low accuracy = fast fix; dawn/wind barely change across a few km.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on Exception {
      return null;
    }
  }

  Future<void> _useGps() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final pos = await _gpsFix();
      if (!mounted) return;
      if (pos == null) {
        setState(() =>
            _error ??= "Couldn't get your location — try search instead");
        return;
      }
      // Reject up front (duplicate / polar) before bothering with a name.
      final err = widget.validate?.call(pos.latitude, pos.longitude);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      final name = await _askName(context);
      if (!mounted || name == null) return;
      // Dialog route is gone but focus/IME may still be unwinding — don't race
      // the bottom-sheet pop against that teardown (fast Save taps hit this).
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      Navigator.of(context).pop(GeoPlace(
        name: name,
        region:
            '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}',
        lat: pos.latitude,
        lon: pos.longitude,
        // The one place that mints a GPS place. Everything downstream reads
        // this rather than sniffing the region string — which is coordinates
        // here precisely because there is no region to quote.
        source: PlaceSource.gps,
      ));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<String?> _askName(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const _NamePlaceDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: _locating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, size: 20),
              title: Text(_locating
                  ? 'Getting your location…'
                  : 'Use my current location'),
              subtitle: const Text(
                'Works offline',
                style: TextStyle(color: AppPalette.textSecondary, fontSize: 12),
              ),
              onTap: _locating ? null : _useGps,
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                onChanged: _onQuery,
                decoration: const InputDecoration(
                  hintText: 'Or search a place…',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const Divider(),
            if (_loading) const LinearProgressIndicator(minHeight: 1),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!,
                    style: const TextStyle(color: AppPalette.textSecondary)),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final p = _results[i];
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text(p.region,
                        style: const TextStyle(
                            color: AppPalette.textSecondary, fontSize: 12)),
                    onTap: () {
                      final err = widget.validate?.call(p.lat, p.lon);
                      if (err != null) {
                        setState(() => _error = err);
                        return;
                      }
                      Navigator.of(context).pop(p);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name dialog for a GPS pick. Stateful so the [TextEditingController] lives
/// until this route's [State.dispose] — disposing in a `finally` after
/// [showDialog] returns raced autofocus teardown and blew up fast Save taps.
class _NamePlaceDialog extends StatefulWidget {
  const _NamePlaceDialog();

  @override
  State<_NamePlaceDialog> createState() => _NamePlaceDialogState();
}

class _NamePlaceDialogState extends State<_NamePlaceDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: 'My location');

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so Save can follow the field (see [_valid]).
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  /// Clearing the field disables Save rather than silently restoring the
  /// default (2026-07-31, Samyak). `My location` is a suggestion you can
  /// accept, not a name that reappears once you've deliberately deleted it —
  /// and a dead Save button says "this needs a name" where a re-substituted
  /// default just looked like the app ignored you.
  bool get _valid => _controller.text.trim().isNotEmpty;

  void _save() {
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('NAME THIS PLACE',
          style: Theme.of(context).textTheme.labelSmall),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(border: InputBorder.none),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _valid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Opens the GPS name dialog alone — for widget tests (same route as production).
@visibleForTesting
Future<String?> showNamePlaceDialogForTest(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _NamePlaceDialog(),
  );
}
