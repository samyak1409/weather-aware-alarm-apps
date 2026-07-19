import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'engine.dart';

/// App state for Nivaat: courts, alarms, history. Every mutation re-runs the
/// engine so the cascade and scheduled rings stay consistent.
class NivaatController extends ChangeNotifier {
  NivaatController({required this.engine});

  final NivaatEngine engine;

  NivaatStore get store => engine.store;

  List<SavedLocation> courts = [];
  List<NivaatAlarm> alarms = [];
  List<HistoryRecord> history = [];
  bool loaded = false;

  SavedLocation? courtById(String id) {
    for (final c in courts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// An already-saved court within ~100 m (true great-circle distance), else
  /// null. Tighter than Arunoday's 1 km: distinct courts can sit close
  /// together, so only reject what is essentially the exact same spot.
  SavedLocation? existingCourtNear(double lat, double lon) {
    for (final c in courts) {
      if (_metersBetween(c.lat, c.lon, lat, lon) < 100) return c;
    }
    return null;
  }

  static double _metersBetween(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  Future<void> init() async {
    await _reload();
    loaded = true;
    notifyListeners();
    // Evaluate in the background; refresh history when done.
    unawaited(resync());
  }

  Future<void> _reload() async {
    courts = await store.loadCourts();
    alarms = await store.loadAlarms();
    history = await store.loadHistory();
  }

  /// Re-runs the whole cascade (app open / resume / ring start-stop / edits).
  Future<void> resync() async {
    // First pull in what background isolates wrote (rows, check state) —
    // this isolate's SharedPreferences cache doesn't see them otherwise, and
    // the engine would re-decide from stale state.
    await store.refresh();
    await engine.evaluateAll();
    history = await store.loadHistory();
    notifyListeners();
  }

  Future<void> addCourt(GeoPlace place) async {
    final court = SavedLocation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: place.name,
      lat: place.lat,
      lon: place.lon,
    );
    courts = [...courts, court];
    await store.saveCourts(courts);
    notifyListeners();
  }

  /// How many alarms are tied to [courtId] (for the delete confirmation).
  int alarmsForCourt(String courtId) =>
      alarms.where((a) => a.courtId == courtId).length;

  /// How many history rows belong to [courtId] (for the delete confirmation).
  /// Keyed by court, so it counts every row for the court — even ones whose
  /// alarm was deleted earlier.
  int historyForCourt(String courtId) =>
      history.where((h) => h.courtId == courtId).length;

  Future<void> removeCourt(String id) async {
    final orphaned = alarms.where((a) => a.courtId == id).toList();
    courts = courts.where((c) => c.id != id).toList();
    alarms = alarms.where((a) => a.courtId != id).toList();
    await store.saveCourts(courts);
    await store.saveAlarms(alarms);
    // Cancel each orphaned alarm's ring + pending checks + cascade state.
    for (final a in orphaned) {
      await engine.evaluateAlarm(a.copyWith(enabled: false), courts);
    }
    // Then delete the court's whole skip/ring log — after the cancels, so
    // nothing re-adds a row for an alarm we just removed.
    await store.removeHistoryForCourt(id);
    history = await store.loadHistory();
    notifyListeners();
  }

  int nextAlarmId() =>
      alarms.isEmpty ? 1 : alarms.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1;

  Future<void> upsertAlarm(NivaatAlarm alarm) async {
    final i = alarms.indexWhere((a) => a.id == alarm.id);
    final previous = i >= 0 ? alarms[i] : null;
    alarms = [...alarms];
    if (i >= 0) {
      alarms[i] = alarm;
    } else {
      alarms.add(alarm);
    }
    await store.saveAlarms(alarms);
    // Edits invalidate the in-flight occurrence: start the cascade fresh.
    // Through the engine (not a blind clearCheckState) so a ring that already
    // fired is finalised into history first — and against the PRE-edit alarm,
    // whose court/thresholds that ring belongs to.
    await engine.discardOccurrence(previous ?? alarm);
    notifyListeners();
    // The wind evaluation hits the network — never block the UI on it.
    unawaited(_evaluateInBackground(alarm));
  }

  Future<void> deleteAlarm(int id) async {
    final removed = alarms.where((a) => a.id == id).toList();
    alarms = alarms.where((a) => a.id != id).toList();
    await store.saveAlarms(alarms);
    notifyListeners();
    for (final a in removed) {
      unawaited(_evaluateInBackground(a.copyWith(enabled: false)));
    }
  }

  Future<void> _evaluateInBackground(NivaatAlarm alarm) async {
    await engine.evaluateAlarm(alarm, courts);
    history = await store.loadHistory();
    notifyListeners();
  }

  Future<void> toggleAlarm(int id, bool enabled) async {
    final i = alarms.indexWhere((a) => a.id == id);
    if (i < 0) return;
    await upsertAlarm(alarms[i].copyWith(enabled: enabled));
  }
}
