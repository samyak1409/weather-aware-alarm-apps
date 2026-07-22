import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'alarm_time_conflict.dart';
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
  /// Per-alarm cascade state (alarm id → in-flight occurrence). Feeds the
  /// home "still checking" cue so it only shows while retries actually run.
  Map<int, CheckState> checkStates = {};
  bool loaded = false;

  SavedLocation? courtById(String id) {
    for (final c in courts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// History, minus any row whose court is gone — and those rows are deleted
  /// for good, not just hidden.
  ///
  /// `removeCourt` already sweeps a court's log, but a **background isolate**
  /// can be mid-check with a stale courts list and land its row just after
  /// that sweep (the store's `upsertHistory` exists because these isolates do
  /// race). The leftover renders as a court-less entry, so every load prunes
  /// (2026-07-22). Called after `store.refresh()` in [resync], which is
  /// exactly when a background write first becomes visible here.
  ///
  /// An EMPTY court list prunes too, and that's deliberate: deleting the last
  /// court already takes its history with it, so with no courts every
  /// surviving row is by definition an orphan. Safe only once [loaded] — before
  /// [init] the in-memory `courts` default is also `[]` even when the store
  /// still has courts, so [resync] must not call this until then (2026-07-23).
  /// Store-side, `[]` can only mean "nothing saved": `_decodeList` returns it
  /// for an absent key and *throws* on corrupt JSON.
  Future<List<HistoryRecord>> _loadHistory() async {
    final rows = await store.loadHistory();
    final live = {for (final c in courts) c.id};
    final orphans = {
      for (final r in rows)
        if (!live.contains(r.courtId)) r.courtId
    };
    if (orphans.isEmpty) return rows;
    for (final id in orphans) {
      await store.removeHistoryForCourt(id);
    }
    return store.loadHistory();
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
    await resync();
  }

  Future<void> _reload() async {
    courts = await store.loadCourts();
    alarms = await store.loadAlarms();
    history = await _loadHistory();
    await _reloadCheckStates();
  }

  Future<void> _reloadCheckStates() async {
    final next = <int, CheckState>{};
    for (final a in alarms) {
      final s = await store.loadCheckState(a.id);
      if (s != null) next[a.id] = s;
    }
    checkStates = next;
  }

  /// Re-runs the whole cascade (app open / resume / ring start-stop / edits).
  Future<void> resync() async {
    // Before [init], `courts` is still the empty default — orphan prune would
    // treat every history row as dead and wipe the log (open-during-ring /
    // early resume / ui-resync ping can all land here). init always resyncs
    // once courts are loaded, so dropping these is safe (2026-07-23).
    if (!loaded) return;
    try {
      // First pull in what background isolates wrote (rows, check state) —
      // this isolate's SharedPreferences cache doesn't see them otherwise, and
      // the engine would re-decide from stale state.
      await store.refresh();
      await engine.evaluateAll();
      history = await _loadHistory();
      await _reloadCheckStates();
      notifyListeners();
    } on Exception catch (e, st) {
      // Never-brick: a wind fetch / plugin hiccup must not take the process
      // down. Programming Errors still propagate. Mitigated: every resume /
      // wakeup re-drives the cascade.
      debugPrint('nivaat resync failed (non-fatal): $e\n$st');
    }
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
    history = await _loadHistory();
    await _reloadCheckStates();
    notifyListeners();
  }

  int nextAlarmId() =>
      alarms.isEmpty ? 1 : alarms.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1;

  /// Returns `false` when [alarm] collides on HH:MM with another alarm
  /// (MESSAGES N20) so callers don't treat a no-op as a successful save.
  Future<bool> upsertAlarm(NivaatAlarm alarm) async {
    // Belt-and-suspenders: the alarm sheet refuses first (N20). Never persist
    // a colliding HH:MM even if a future caller skips the UI check.
    if (nivaatAlarmTimeConflict(alarms, alarm) != null) return false;

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
    // Drop stale in-flight state before notify so the home cue can't flash
    // "still checking" for an occurrence we just discarded (toggle / edit).
    await _reloadCheckStates();
    notifyListeners();
    // The wind evaluation hits the network — never block the UI on it.
    unawaited(_evaluateInBackground(alarm));
    return true;
  }

  Future<void> deleteAlarm(int id) async {
    final removed = alarms.where((a) => a.id == id).toList();
    alarms = alarms.where((a) => a.id != id).toList();
    await store.saveAlarms(alarms);
    checkStates = {
      for (final e in checkStates.entries)
        if (e.key != id) e.key: e.value
    };
    notifyListeners();
    for (final a in removed) {
      unawaited(_evaluateInBackground(a.copyWith(enabled: false)));
    }
  }

  Future<void> _evaluateInBackground(NivaatAlarm alarm) async {
    await engine.evaluateAlarm(alarm, courts);
    history = await _loadHistory();
    await _reloadCheckStates();
    notifyListeners();
  }

  Future<void> toggleAlarm(int id, bool enabled) async {
    final i = alarms.indexWhere((a) => a.id == id);
    if (i < 0) return;
    // Same id / same HH:MM → conflict helper always allows; don't ignore the
    // bool (unused_result hygiene + catches a broken guard if it ever fires).
    final ok = await upsertAlarm(alarms[i].copyWith(enabled: enabled));
    assert(ok, 'toggleAlarm must never hit an HH:MM conflict');
  }
}
