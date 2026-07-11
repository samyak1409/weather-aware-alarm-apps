import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'open_meteo.dart';
import 'theme.dart';

/// Shared bottom-sheet place picker: GPS ("use my current location", works
/// fully offline — GPS is satellite-based) or Open-Meteo geocoding search
/// (for places you aren't standing at). Returns the picked [GeoPlace], or
/// null if dismissed.
Future<GeoPlace?> showLocationSearch(BuildContext context) {
  return showModalBottomSheet<GeoPlace>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _LocationSearchSheet(),
  );
}

class _LocationSearchSheet extends StatefulWidget {
  const _LocationSearchSheet();

  @override
  State<_LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<_LocationSearchSheet> {
  final _api = OpenMeteo();
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
        final results = await _api.geocode(q.trim());
        if (mounted) setState(() => _results = results);
      } catch (_) {
        if (mounted) setState(() => _error = 'Search failed — check network');
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
        setState(() => _error ??= 'Could not get a GPS fix — try search');
        return;
      }
      final name = await _askName(context);
      if (!mounted || name == null) return;
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
    final controller = TextEditingController(text: 'My location');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('NAME THIS PLACE',
            style: Theme.of(context).textTheme.labelSmall),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: InputBorder.none),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.pop(context, name.isEmpty ? 'My location' : name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
                  ? 'Getting a GPS fix…'
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
                    onTap: () => Navigator.of(context).pop(p),
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
