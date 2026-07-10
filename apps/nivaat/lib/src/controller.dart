import 'dart:async';

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

  /// Re-runs the whole cascade (app open / resume / after edits).
  Future<void> resync() async {
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

  Future<void> removeCourt(String id) async {
    courts = courts.where((c) => c.id != id).toList();
    await store.saveCourts(courts);
    // Alarms pointing at the removed court get their rings cancelled.
    for (final a in alarms.where((a) => a.courtId == id)) {
      await engine.evaluateAlarm(a, courts);
    }
    notifyListeners();
  }

  int nextAlarmId() =>
      alarms.isEmpty ? 1 : alarms.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1;

  Future<void> upsertAlarm(NivaatAlarm alarm) async {
    final i = alarms.indexWhere((a) => a.id == alarm.id);
    alarms = [...alarms];
    if (i >= 0) {
      alarms[i] = alarm;
    } else {
      alarms.add(alarm);
    }
    await store.saveAlarms(alarms);
    // Edits invalidate the in-flight occurrence: start the cascade fresh.
    await store.clearCheckState(alarm.id);
    await engine.evaluateAlarm(alarm, courts);
    notifyListeners();
  }

  Future<void> deleteAlarm(int id) async {
    final removed = alarms.where((a) => a.id == id).toList();
    alarms = alarms.where((a) => a.id != id).toList();
    await store.saveAlarms(alarms);
    for (final a in removed) {
      await engine.evaluateAlarm(a.copyWith(enabled: false), courts);
    }
    notifyListeners();
  }

  Future<void> toggleAlarm(int id, bool enabled) async {
    final i = alarms.indexWhere((a) => a.id == id);
    if (i < 0) return;
    await upsertAlarm(alarms[i].copyWith(enabled: enabled));
  }
}
