import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alarmkit/flutter_alarmkit.dart';

import 'alarm_pkg_scheduler.dart';
import 'db/app_database.dart';
import 'host_alarm_events.dart';
import 'scheduler.dart';

/// [AlarmScheduler] backed by Apple AlarmKit (iOS 26+): system-rung alarms
/// that break through Silent mode and Focus, show full-screen, and survive
/// app termination and reboot.
///
/// AlarmKit has no per-alarm volume; [soundAssetForVolume] maps the engine's
/// volume (Nivaat's wind ramp) to a pre-rendered loudness variant. AlarmKit
/// also assigns its own UUIDs, so an int-id -> UUIDs map is persisted — see
/// [_loadMap] for why each id holds a list rather than one.
class AlarmKitScheduler implements AlarmScheduler {
  AlarmKitScheduler({
    required this.soundAssetForVolume,
    required this.tintColor,
  });

  /// e.g. volume 0.85 -> 'assets/sounds/nivaat_ring_85.wav'. Unlike
  /// `AlarmPkgScheduler`, this one really does need the volume: AlarmKit has
  /// no volume knob, so the ramp can only arrive baked into the file.
  final String Function(double volume) soundAssetForVolume;

  /// '#RRGGBB' accent used on the system alarm UI.
  final String tintColor;

  final FlutterAlarmkit _ak = FlutterAlarmkit();
  bool _authRequested = false;

  /// Resolved per call so a test swapping the database in `setUp` is seen.
  AppDatabase get _db => appDb;

  @override
  Future<void> ensureInitialized() async {
    if (_authRequested) return;
    final state = await _ak.getAuthorizationState();
    if (state == AlarmAuthorizationState.notDetermined) {
      await _ak.requestAuthorization();
    }
    _authRequested = true;
  }

  /// The whole id -> UUIDs map, each id's handles **newest first**.
  ///
  /// **One row per handle, not one blob for the whole map** — that is what
  /// moving to SQLite bought here. The prefs version was a read-edit-save over
  /// every id at once, so a background isolate writing one id's entry saved the
  /// UI isolate's other ids away with it (REVIEW #7); reloading first narrowed
  /// that window but could not close it, because prefs has no compare-and-swap.
  /// Two ids can no longer contend at all, and an add or a remove is one
  /// statement.
  ///
  /// **The create -> save window is NOT closed by any of this.** AlarmKit mints
  /// the UUID, so there is still nothing to write down until
  /// `scheduleOneShotAlarm` returns, and dying in that gap still leaves an
  /// armed alarm no row names. Do not read "we moved it to SQLite" as "that one
  /// is fixed" — only the concurrent half is. See [scheduleRing].
  ///
  /// **Each id holds a LIST** (REVIEW #4 · #5 · #6): the live UUID plus any
  /// whose cancel was not confirmed. One slot per id could not hold "keep the
  /// old handle when its cancel fails" and "create the replacement before
  /// destroying what it replaces" at once — both want it — so every operation
  /// here treats the whole list alike: cancel them all, ask them all whether one
  /// is ringing, prune what AlarmKit has forgotten.
  Future<Map<String, List<String>>> _loadMap() async {
    final rows = await (_db.select(_db.alarmKitHandles)
          ..orderBy([(t) => OrderingTerm.desc(t.seq)]))
        .get();
    final out = <String, List<String>>{};
    for (final row in rows) {
      (out['${row.alarmId}'] ??= <String>[]).add(row.uuid);
    }
    return out;
  }

  /// Records [uuid] as [id]'s newest handle.
  ///
  /// One transaction so the sequence number cannot be handed out twice, and
  /// scoped to this id: another alarm's handles are untouched, which is the
  /// whole difference from the blob.
  Future<void> _addHandle(int id, String uuid) => _db.transaction(() async {
        final seq = await _db
            .customSelect(
              'SELECT COALESCE(MAX(seq), 0) + 1 AS next FROM alarm_kit_handles '
              'WHERE alarm_id = ?',
              variables: [Variable.withInt(id)],
            )
            .getSingle();
        await _db.into(_db.alarmKitHandles).insertOnConflictUpdate(
              AlarmKitHandlesCompanion(
                alarmId: Value(id),
                uuid: Value(uuid),
                seq: Value(seq.read<int>('next')),
                createdAt: Value(DateTime.now()),
              ),
            );
      });

  /// Forgets [uuids] under [id]. An id with nothing left simply has no rows,
  /// which is what "we hold no handle on it" means — there is no empty-list
  /// case to filter out any more.
  Future<void> _removeHandles(int id, Set<String> uuids) async {
    if (uuids.isEmpty) return;
    await (_db.delete(_db.alarmKitHandles)
          ..where((t) => t.alarmId.equals(id) & t.uuid.isIn(uuids)))
        .go();
  }

  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async {
    await ensureInitialized();
    // **Create the replacement BEFORE destroying what it replaces** (REVIEW
    // #5): a failed create then leaves the old alarm armed and mapped instead
    // of leaving the day silent. Do not "tidy" the order back — the accepted
    // cost is the mirror image (a failed cancel leaves two live alarms, both
    // sounding), and a duplicate alert beats an alarm that never sounds.
    // CLAUDE.md.
    final String uuid;
    try {
      uuid = await _ak.scheduleOneShotAlarm(
        timestamp: at.millisecondsSinceEpoch.toDouble(),
        label: title,
        tintColor: tintColor,
        // AlarmKit has no volume knob, so loudness can only arrive baked into
        // the file — and a null volume means "no opinion", which is the
        // unattenuated master. iOS then plays it at the system alarm volume,
        // which is exactly what an app with no opinion should get.
        soundPath: soundAssetForVolume(volume ?? 1),
      );
    } on PlatformException {
      // AlarmKit denied or unavailable. By design there is NO `alarm`-package
      // fallback on iOS (2026-07-18 decision) — instead [alarmSchedulingDenied]
      // drives the permission banner to send the user to Settings. A failed
      // schedule must never crash the engine/controller, but it must not pass
      // for a success either: this used to `return` into a caller that then
      // recorded the alarm as armed, and Nivaat logged `Rang` for an
      // occurrence that never made a sound (REVIEW #2).
      return false;
    }
    final superseded = (await _loadMap())['$id'] ?? const <String>[];
    // Record the new handle BEFORE cancelling anything, so a crash in the gap
    // leaves an alarm we can still name.
    //
    // **The create→save window above is the one leak left, and it cannot be
    // closed here:** AlarmKit mints the UUID, so nothing can be written down
    // until the create returns, and dying in between (iOS killing a background
    // task at expiry) arms an alarm no row names — so nothing can cancel it and
    // it rings even when the wind says to skip. Sweeping alarms this map
    // does not name is the only fix and is NOT a drive-by: in that same
    // window a new alarm looks exactly like an orphan. CLAUDE.md.
    //
    // Moving the map into SQLite did not change any of that. It closed the
    // *concurrent* half — two isolates clobbering each other's entries — and
    // left this crash window exactly where it was.
    await _addHandle(id, uuid);
    await _cancelEach(id, superseded);
    return true;
  }

  /// Cancels every alarm still held for [id], and **keeps the handle of any
  /// that refuses**.
  ///
  /// `cancelAlarm` signals failure BOTH by returning false and by throwing,
  /// and dropping the entry before consulting either left the alarm unreachable
  /// for good — its UUID is the only handle there is (REVIEW #6). Keeping it
  /// costs nothing: [scheduledIds] prunes what AlarmKit has forgotten, so the
  /// failure mode is a retry, not a leak.
  @override
  Future<void> cancel(int id) async {
    final map = await _loadMap();
    await _cancelEach(id, map['$id'] ?? const <String>[]);
  }

  /// Cancels [uuids] one by one and removes from [id]'s entry only the ones
  /// AlarmKit confirmed are gone. Best effort by design: whatever survives
  /// stays mapped, so the next cancel — or the next sweep — reaches it again.
  Future<void> _cancelEach(int id, List<String> uuids) async {
    if (uuids.isEmpty) return;
    final gone = <String>{};
    for (final uuid in uuids) {
      bool cancelled;
      try {
        cancelled = await _ak.cancelAlarm(alarmId: uuid);
      } on PlatformException {
        // Includes "already gone" (fired, or the user removed it), which is
        // indistinguishable here from a real error — so treat it as unresolved
        // and let the sweep decide, rather than guessing in the direction that
        // loses the handle.
        cancelled = false;
      }
      if (cancelled) gone.add(uuid);
    }
    // A targeted DELETE of exactly what AlarmKit confirmed is gone. The prefs
    // version had to re-read the whole map here and write it back, because the
    // cancels above take real time and it was rebuilding a blob it might have
    // read before another isolate wrote it (REVIEW #7). Naming the rows removes
    // both the re-read and the race.
    await _removeHandles(id, gone);
  }

  /// The int ids AlarmKit still holds something for, pruned by [_livingMap].
  /// Nivaat's orphan sweep runs this every pass.
  @override
  Future<Set<int>> scheduledIds() async {
    try {
      return (await _livingMap()).map.keys.map(int.parse).toSet();
    } on PlatformException {
      // The sweep this feeds decides what to CANCEL, and cancelling nothing is
      // safe — so unlike [scheduledAlarms] this one may answer "none" when the
      // platform cannot be asked.
      return {};
    }
  }

  /// The map with everything AlarmKit has forgotten removed, plus AlarmKit's
  /// own alarms by UUID so a caller can read each one's state or date.
  ///
  /// **Pruning lives here, not in one caller.** It used to sit inside
  /// [scheduledIds], which was fine while that was the only batch read — then
  /// [scheduledAlarms] arrived, Arunoday moved onto it, and Arunoday stopped
  /// pruning entirely. On iOS a fired-and-dismissed alarm's `cancelAlarm`
  /// cannot be distinguished from a real failure, so its UUID is deliberately
  /// kept (REVIEW #6); without a prune those dead handles accumulate under the
  /// id forever and every later `cancel` retries all of them.
  ///
  /// **Prunes only what AlarmKit no longer knows AT ALL** (REVIEW #4). Keeping
  /// just `AlarmState.scheduled` dropped the UUID of the alarm sounding right
  /// now, blinding [isRinging] and putting the live alert beyond [cancel].
  /// Every other state is still ours — including `unknown`, which is how a
  /// state a future iOS adds arrives, so pruning on it would wipe the whole map
  /// on the first resync.
  Future<({Map<String, List<String>> map, Map<String, Alarm> byUuid})>
      _livingMap() async {
    // **Taken BEFORE the query, and that ordering is the whole guard.** What
    // comes back is a snapshot, and deleting "everything AlarmKit did not
    // mention" against a snapshot destroys any handle another isolate recorded
    // in the meantime — an armed alarm no row names, which `cancel`,
    // `isRinging` and the orphan sweep all work off, so it rings when the wind
    // says to skip. `scheduleRing` records its row only after
    // `scheduleOneShotAlarm` has returned, so a row older than this instant was
    // already known to AlarmKit when it was asked; anything newer is not this
    // snapshot's business and is left alone until the next prune.
    final asOf = DateTime.now().microsecondsSinceEpoch;
    // Ask AlarmKit FIRST: a failure here must throw before anything is deleted,
    // or a transient hiccup would prune the whole map as "forgotten".
    final alarms = await _ak.getAlarms();
    final byUuid = {for (final a in alarms) a.id: a};
    final live = byUuid.keys.toList();
    // `NOT IN ()` is a syntax error in SQLite, so the empty case is spelled
    // out: AlarmKit holding nothing means every handle we have is dead.
    final prune = _db.delete(_db.alarmKitHandles)
      ..where((t) => t.createdAt.isSmallerThanValue(asOf));
    if (live.isNotEmpty) prune.where((t) => t.uuid.isNotIn(live));
    await prune.go();
    // The prefs version wrote only when something had actually gone, because
    // every save of that blob was another chance for two isolates to overwrite
    // each other. A DELETE that names the rows it removes cannot catch a
    // bystander, so there is nothing left for that guard to protect.
    return (map: await _loadMap(), byUuid: byUuid);
  }

  @override
  Future<bool> isRinging(int id) async {
    final map = await _loadMap();
    // ANY of this id's alarms, not just the newest: a replacement whose cancel
    // was refused leaves an older one live, and if that is what the user can
    // hear then this id is ringing. Answering "no" would let the cascade
    // cancel a ring that is physically sounding.
    final uuids = map['$id'] ?? const <String>[];
    if (uuids.isEmpty) return false;
    // **A failed query THROWS rather than answering "not ringing"**, the same
    // rule [scheduledAlarms] follows and for a worse reason: every caller of
    // this is asking permission to destroy something. `_cancelExcept` and the
    // orphan sweep both read `false` as "safe to cancel", so swallowing a
    // transient AlarmKit error here silences an alarm that is physically
    // sounding — which is exactly what this method was written to prevent
    // (REVIEW #3 · #4). A throw aborts the pass instead, and every pass here
    // is rebuilt from scratch on the next one.
    final alarms = await _ak.getAlarms();
    for (final a in alarms) {
      if (uuids.contains(a.id) && a.state == AlarmState.alerting) return true;
    }
    return false;
  }

  /// **False — AlarmKit tells us nothing it did on its own.** There is no iOS
  /// equivalent of `Alarm.events`: no boot receiver to discard a stale alarm,
  /// no foreground-service refusal to defer one, and no marker drained at
  /// init. So on iOS "the ring is no longer there" carries no information
  /// about whether it rang — it is what an ordinary dismissed alarm looks
  /// like — and Nivaat must not read it as a miss. Getting this wrong labels
  /// every iOS ring `Couldn't confirm`, because AlarmKit never opens the
  /// app and so the app is essentially never running while the alert sounds.
  @override
  bool get reportsHostEvents => false;

  @override
  Future<void> applyHostAlarmEvents() async {}

  /// What AlarmKit still holds, per int id, with each alarm's own fire date.
  ///
  /// **A `null` here used to be unconditional, and that was a real hazard**:
  /// Nivaat reads "the plugin has nothing for this id" as evidence the ring is
  /// gone, so a late ring armed for ten seconds' time was read as vanished and
  /// the occurrence closed out from under it. Only [FixedAlarmSchedule] can
  /// answer the question — a relative or unknown schedule has no single
  /// instant — and every alarm this class creates is a one-shot, so anything
  /// else is a handle we should keep but cannot date.
  /// **A failed query THROWS rather than answering "nothing is armed".**
  ///
  /// [scheduledIds] may swallow the same failure because it feeds the orphan
  /// sweep, where the worst case is cancelling nothing. This one feeds the
  /// opposite decision: Nivaat reads an absent id as "the ring is gone" and
  /// closes the occurrence on it. Returning an empty map on a transient
  /// AlarmKit hiccup would finalise an occurrence whose alarm is still sitting
  /// in the system, armed and about to sound — "I could not ask" is not "it is
  /// not there", which is REVIEW #2's rule pointed at a different call.
  @override
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms() async {
    final living = await _livingMap();
    final out = <int, ScheduledAlarmInfo>{};
    for (final e in living.map.entries) {
      final id = int.parse(e.key);
      // Newest first, so the first datable one is the live handle. An older
      // UUID whose cancel was refused is still ours, but the newest is what
      // this id means now.
      for (final uuid in e.value) {
        final schedule = living.byUuid[uuid]?.schedule;
        if (schedule is FixedAlarmSchedule) {
          out[id] = ScheduledAlarmInfo(
            id: id,
            dateTime: schedule.date,
            // Every handle AlarmKit still knows, not just the datable newest:
            // a refused cancel leaves an older alarm live under this same id.
            handles: e.value.length,
          );
          break;
        }
      }
    }
    return out;
  }

  @override
  void setHostAlarmEventHandler(
    Future<void> Function(HostAlarmEvent event)? handler,
  ) {}
}

/// Picks the scheduler for the platform: **AlarmKit on iOS** (min target 26,
/// so always present), the `alarm` package on Android. iOS has **no**
/// `alarm`-package fallback (2026-07-18): if the user denies AlarmKit,
/// scheduling silently no-ops and [alarmSchedulingDenied] lets the UI nudge
/// them to Settings — we never ship the `alarm` package's unreliable
/// Timer-based iOS ring.
Future<AlarmScheduler> createAlarmScheduler({
  required String Function(double volume) soundAssetForVolume,
  required String tintColor,
}) async {
  if (Platform.isIOS) {
    return AlarmKitScheduler(
      soundAssetForVolume: soundAssetForVolume,
      tintColor: tintColor,
    );
  }
  return AlarmPkgScheduler(soundAssetForVolume: soundAssetForVolume);
}

/// True only when the user has **denied** AlarmKit on iOS — the signal for
/// [AlarmPermissionBanner]. Android, and any non-denied iOS state
/// (authorized / not-yet-asked), → false.
Future<bool> alarmSchedulingDenied() async {
  if (!Platform.isIOS) return false;
  try {
    final state = await FlutterAlarmkit().getAuthorizationState();
    return state == AlarmAuthorizationState.denied;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
