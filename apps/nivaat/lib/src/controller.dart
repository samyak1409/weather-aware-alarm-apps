import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'alarm_time_conflict.dart';
import 'engine.dart';
import 'ids.dart';

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

  /// Most recent fire-and-forget cleanup or evaluate kicked off by
  /// [upsertAlarm] or [deleteAlarm] (or null before the first). Tests await
  /// this; production never reads it.
  ///
  /// [deleteAlarm] publishes its handle here for a reason: without one its
  /// disarming was untestable, so nothing asserted that deleting an alarm
  /// takes down the ring it already had (REVIEW #23).
  @visibleForTesting
  Future<void>? lastEvaluation;

  SavedLocation? courtById(String id) {
    for (final c in courts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The court behind a **ring** id, for the ring screen's label (X1, N1) —
  /// null when [ringId] is not a ring at all, or its alarm or court has gone.
  ///
  /// Ring ids, not alarm ids: what the ring screen holds is an `AlarmSettings`
  /// straight from the plugin, so it carries the locker number
  /// ([NivaatIds.ring] / `lateRing` / `nextRing`) rather than the alarm's own.
  ///
  /// Reads the store's live lists, so a ring that cold-started the app shows
  /// its court as soon as [init] has loaded them — see `RingGate.alarmLabel`.
  String? courtNameForRing(int ringId) {
    final alarmId = NivaatIds.alarmIdOfRing(ringId);
    if (alarmId == null) return null;
    for (final a in alarms) {
      if (a.id == alarmId) return courtById(a.courtId)?.name;
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
  /// (2026-07-22). It used to say this ran after `store.refresh()` in [resync],
  /// "exactly when a background write first becomes visible here" — that call
  /// went with the move to SQLite (2026-08-12), and a background write is
  /// visible to any read now.
  ///
  /// An EMPTY court list prunes too, and that's deliberate: deleting the last
  /// court already takes its history with it, so with no courts every
  /// surviving row is by definition an orphan. Safe only once [loaded] — before
  /// [init] the in-memory `courts` default is also `[]` even when the store
  /// still has courts, so [resync] must not call this until then (2026-07-23).
  /// Store-side, `[]` can only mean "nothing saved": it is an empty table, and
  /// there is no half-read blob that could present as one.
  Future<List<HistoryRecord>> _loadHistory() async {
    // This reads the database, so a row a background check committed a moment
    // ago is simply here. It used to need `store.refresh()` first, because
    // SharedPreferences caches per isolate and this method PRUNES — deciding
    // what to throw away from a stale read is the same mistake as writing over
    // one (REVIEW #7).
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

  /// N21's refusal, or null to accept the place. Lives here, not inline in the
  /// courts sheet, for the reason this repo keeps relearning: a string built
  /// inside a widget is a string no test can name (2026-07-31).
  ///
  /// "Area" rather than a distance: the rule is a ~100 m radius, and no
  /// wording of "within 100 m" survives contact with a user who is standing
  /// at the other end of the same park.
  String? courtRefusal(double lat, double lon) {
    final dup = existingCourtNear(lat, lon);
    return dup == null ? null : 'Same area as ${dup.name} — already added.';
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
    // Nothing saved = nothing ever saved an alarm, so start at 1. **Never
    // derive it from the alarms** — "highest + 1" IS the bug [nextAlarmId]
    // kills, and it returns the moment anything recomputes it, since deleting
    // the newest alarm drops the highest with it. [upsertAlarm] keeps the
    // counter ahead of every stored id, so there is nothing here to heal, and
    // alarms-with-no-counter is deliberately neither asserted nor thrown on —
    // [nextAlarmId] already makes that state cost a number rather than an alarm.
    _alarmIdSeq = await store.loadAlarmIdSeq() ?? 1;
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

  /// The next alarm id to hand out. Loaded in [_reload], advanced and persisted
  /// by [upsertAlarm] — never by this getter.
  int _alarmIdSeq = 1;

  /// The id a NEW alarm would be given (REVIEW #9).
  ///
  /// **Pure — asking twice gives the same answer**, which the alarm sheet
  /// depends on: it mints the id once for the live HH:MM conflict check and
  /// again for the alarm it saves, and those two disagreeing would check one
  /// alarm and write another. So the counter advances on SAVE, not here.
  ///
  /// It used to be "highest existing + 1", which handed a deleted alarm's
  /// number to the next one created — and since every id here is
  /// `block + alarmId`, the new alarm inherited its ring, checks and card: a
  /// fresh 07:00 could pick up the ring armed for the 06:30 you just deleted.
  ///
  /// **One rule: never hand out a number a live alarm already holds.** The
  /// counter satisfies it on its own in every state this build can produce —
  /// it is saved before the alarm that spends it, so it is always past every
  /// stored id.
  int nextAlarmId() {
    final used = {for (final a in alarms) a.id};
    if (_alarmIdSeq <= NivaatIds.maxAlarmId && !used.contains(_alarmIdSeq)) {
      return _alarmIdSeq;
    }
    // Two ways here. Past the ceiling, `ring(10001)` would BE `lateRing(1)`
    // (REVIEW #21). And a counter standing on a LIVE alarm — storage this build
    // cannot write, which is what lets [_reload] stay quiet about it — would
    // otherwise be silent damage: `upsertAlarm` reads a colliding id as an EDIT
    // and overwrites the alarm already wearing it. A free number always exists,
    // since N18 caps coexisting alarms at 1440 inside a 9999-wide block.
    var id = 1;
    while (used.contains(id)) {
      id++;
    }
    return id;
  }

  /// Returns `false` when [alarm] collides on HH:MM with another alarm
  /// (MESSAGES N18) so callers don't treat a no-op as a successful save.
  ///
  /// Pass [now] in tests to pin wall-clock decisions (abandon vs continue,
  /// and the follow-up evaluate). Production callers leave it null.
  ///
  /// The follow-up evaluate is always fire-and-forget (same as production) —
  /// await [lastEvaluation] in tests when you need its outcome. [now] only
  /// chooses the clock; it does not change concurrency.
  Future<bool> upsertAlarm(NivaatAlarm alarm, {DateTime? now}) async {
    // Belt-and-suspenders: the alarm sheet refuses first (N18). Never persist
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
    // **The id and the alarm that spends it are now ONE write** (REVIEW #9).
    // They used to be two, deliberately ordered counter-first: interrupted
    // between them, one number is skipped and nothing is lost, where the other
    // order leaves an alarm with no counter past it and the next alarm created
    // takes its number — inheriting its ring, late ring, check, card and
    // cascade state. There is no "between" any more; both land or neither does.
    // Nothing re-derives the counter afterwards to paper over it either (see
    // [_reload]) — "highest + 1" IS the bug, whatever it is spelled as.
    //
    // Guarded because most calls here are EDITS (every toggle is one), which
    // must leave the counter alone. `>=` not `>`: the id being handed out right
    // now is `_alarmIdSeq` itself.
    final burnsId = alarm.id >= _alarmIdSeq;
    if (burnsId) _alarmIdSeq = alarm.id + 1;
    await store.saveAlarms(alarms, alarmIdSeq: burnsId ? _alarmIdSeq : null);
    // Mid-window: limit / Keep checking / add-only weekdays KEEP flying under
    // the new settings. Time, court, drop-today and toggle-off ABANDON — the
    // card is rewritten to `Cancelled` and a matching row appended, because
    // the alarm still exists and deserves an explanation. (Delete is the
    // opposite and takes the card down; see [deleteAlarm].) A brand-new alarm
    // has no occurrence to abandon, so this is just a cheap clear.
    //
    // CheckState is read outside the engine's per-alarm queue — benign: both
    // branches re-read inside the lane, so a stale classify degrades to a
    // no-op (retain finds nothing / abandon clears an already-cleared id).
    final prior = previous;
    if (prior == null) {
      await engine.abandonOccurrence(alarm, now: now, keepCard: true);
    } else {
      final state = await store.loadCheckState(alarm.id);
      if (nivaatEditAbandonsInFlight(prior, alarm, state: state, now: now)) {
        await engine.abandonOccurrence(prior, now: now, keepCard: true);
      } else {
        await engine.retainInFlightEdits(prior, alarm, now: now);
      }
    }
    // Drop stale in-flight state before notify so the home cue can't flash
    // "still checking" for an occurrence we just abandoned (toggle / edit).
    await _reloadCheckStates();
    notifyListeners();
    // Wind evaluation hits the network — never block the UI on it. Tests
    // await [lastEvaluation] when they need the late-ring / finalise outcome.
    lastEvaluation = _evaluateInBackground(alarm, now: now);
    unawaited(lastEvaluation!);
    return true;
  }

  /// Deleting mid-window still closes the morning's story — the history rows
  /// survive an alarm's deletion, so leaving the last one open would strand a
  /// row reading "watching until 06:30" that nothing will ever answer. What it
  /// does NOT do is keep the card: a notification for an alarm that no longer
  /// exists is an orphan, which is the bug that started all this.
  Future<void> deleteAlarm(int id) async {
    final removed = alarms.where((a) => a.id == id).toList();
    alarms = alarms.where((a) => a.id != id).toList();
    await store.saveAlarms(alarms);
    checkStates = {
      for (final e in checkStates.entries)
        if (e.key != id) e.key: e.value
    };
    notifyListeners();
    // Fire-and-forget in production — a delete must feel instant — but the
    // handle is kept so a test can await the disarming it triggers.
    lastEvaluation = Future.wait([
      for (final a in removed)
        () async {
          await engine.abandonOccurrence(a);
          await _evaluateInBackground(a.copyWith(enabled: false));
        }(),
    ]);
    unawaited(lastEvaluation!);
  }

  Future<void> _evaluateInBackground(NivaatAlarm alarm, {DateTime? now}) async {
    await engine.evaluateAlarm(alarm, courts, now: now);
    history = await _loadHistory();
    await _reloadCheckStates();
    notifyListeners();
  }

  Future<void> toggleAlarm(int id, bool enabled, {DateTime? now}) async {
    final i = alarms.indexWhere((a) => a.id == id);
    if (i < 0) return;
    // Same id / same HH:MM → conflict helper always allows; don't ignore the
    // bool (unused_result hygiene + catches a broken guard if it ever fires).
    final ok =
        await upsertAlarm(alarms[i].copyWith(enabled: enabled), now: now);
    assert(ok, 'toggleAlarm must never hit an HH:MM conflict');
  }
}
