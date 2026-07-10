import 'dart:async';

import 'package:flutter/material.dart';

import 'open_meteo.dart';
import 'theme.dart';

/// Shared bottom-sheet place search (Open-Meteo geocoding). Returns the
/// picked [GeoPlace], or null if dismissed.
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: TextField(
                autofocus: true,
                onChanged: _onQuery,
                decoration: const InputDecoration(
                  hintText: 'Search a place…',
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
