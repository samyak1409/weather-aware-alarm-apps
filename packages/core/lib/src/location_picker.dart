import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final results = await widget.api.geocode(q.trim());
        if (mounted) setState(() => _results = results);
      } catch (e, st) {
        reportLocationSearchFailure(
          e,
          (msg) {
            if (mounted) setState(() => _error = msg);
          },
          stackTrace: st,
        );
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<Position?> _gpsFix() async {
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
    try {
      // Low accuracy = fast fix; dawn/wind barely change across a few km.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on Exception {
      return Geolocator.getLastKnownPosition();
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    FocusScope.of(context).unfocus();
    final name = _controller.text.trim();
    Navigator.pop(context, name.isEmpty ? 'My location' : name);
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
          onPressed: _save,
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
