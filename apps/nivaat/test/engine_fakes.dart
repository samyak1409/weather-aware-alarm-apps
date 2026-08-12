import 'dart:async';

import 'package:core/core.dart';
import 'package:nivaat/src/check_scheduler.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/ids.dart';
import 'package:nivaat/src/skip_notifier.dart';

/// Mark armed lockers ringing and re-evaluate so Rule 1 settles pending → Rang.
/// Post-T `scheduleRing` success no longer writes history immediately.
Future<void> settleAudibleRing({
  required FakeRing ring,
  required NivaatEngine engine,
  required NivaatAlarm alarm,
  required List<SavedLocation> courts,
  required DateTime now,
}) async {
  final pending = await engine.store.loadPendingRing(alarm.id);
  if (pending != null) {
    ring.ringingIds.add(pending.pluginId);
  } else {
    for (final id in NivaatIds.allRings(alarm.id)) {
      if (ring.scheduled.containsKey(id)) ring.ringingIds.add(id);
    }
  }
  await engine.evaluateAlarm(alarm, courts, now: now);
}

/// Recording doubles shared by the engine tests. They live outside any
/// `_test.dart` file on purpose: importing one test file from another works,
/// but it compiles a second `main` into the importer and reads like an
/// accident. Same reason `silent_fakes.dart` exists next door — these are the
/// noisy half (they remember what they were asked to do), those are the quiet
/// half (they no-op).

class FakeNotifier extends SkipNotifier {
  final List<
      ({
        String status,
        String body,
        HistoryRecord record,
        String court
      })> pushes = [];
  final List<int> cancelled = [];

  /// The card as it stands now: the last push, unless something cancelled it.
  ({String status, String body, HistoryRecord record, String court})? get card =>
      _live ? (pushes.isEmpty ? null : pushes.last) : null;
  bool _live = false;

  Iterable<String> get bodies => pushes.map((p) => p.body);

  /// Views by state, so the cascade tests can keep asking "has the morning
  /// opened / closed yet?". These count PUSHES to the one card, not separate
  /// notifications — `extended` is every still-checking push, `shown` every
  /// skipped push.
  List<(HistoryRecord, String)> get extended => [
        for (final p in pushes)
          if (p.status == kNivaatStillChecking) (p.record, p.court)
      ];
  List<(HistoryRecord, String)> get shown => [
        for (final p in pushes)
          if (p.status == kNivaatSkipped) (p.record, p.court)
      ];

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> showStillChecking(
      HistoryRecord record, String courtName, DateTime until) async {
    _live = true;
    pushes.add((
      status: kNivaatStillChecking,
      body: nivaatStillCheckingBody(record, until),
      record: record,
      court: courtName,
    ));
  }

  @override
  Future<void> showSkipped(HistoryRecord record, String courtName) async {
    final body = nivaatSkippedBody(record);
    if (body.isEmpty) return;
    _live = true;
    pushes.add((
      status: kNivaatSkipped,
      body: body,
      record: record,
      court: courtName,
    ));
  }

  @override
  Future<void> showCancelled(HistoryRecord record, String courtName) async {
    _live = true;
    pushes.add((
      status: kNivaatCancelled,
      body: nivaatCancelledBody(record),
      record: record,
      court: courtName,
    ));
  }

  @override
  Future<void> cancelForAlarm(int alarmId) async {
    _live = false;
    cancelled.add(alarmId);
  }
}

class FakeRing implements AlarmScheduler {
  final Map<int, ({DateTime at, double? volume, String title, String body})>
      scheduled = {};

  /// Every scheduleRing call in order — [scheduled] only keeps the latest per
  /// id, which hides e.g. a late ring that finalising then rolls over.
  final List<({int id, DateTime at})> log = [];

  /// Every cancel in order. Needed because a cancel can be immediately
  /// followed by a write to the same locker inside one pass, which [scheduled]
  /// alone cannot distinguish from "never cancelled".
  final List<int> cancelled = [];
  final Set<int> ringingIds = {};

  @override
  Future<void> ensureInitialized() async {}

  /// Whether a booking succeeds. Flip it to drive the REVIEW #2 path: a
  /// scheduler that reports failure must leave the occurrence unarmed.
  bool accepts = true;

  /// Whether a REFUSED booking also destroys what the locker held. True is
  /// Android (`Alarm.set` stops first); false is AlarmKit (schedules first,
  /// so a failed create leaves the old alarm live). See [scheduleRing].
  bool destructiveOnFailure = true;

  /// Makes [scheduleRing] THROW rather than decline.
  ///
  /// [accepts] models a booking the platform refuses, which the engine handles
  /// by leaving the occurrence open; this models the plugin call itself
  /// failing, which propagates. The two reach different code — an outbox
  /// handler only retries what throws.
  bool throwOnSchedule = false;

  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async {
    if (throwOnSchedule) throw Exception('plugin call failed');
    if (!accepts) {
      // **The two platforms fail in OPPOSITE directions, and this fake must
      // not pretend otherwise.** On Android `Alarm.set` stops the same id
      // before it schedules, so a refusal leaves the locker empty — modelled
      // by [destructiveOnFailure], the default, because a fake that merely
      // declined would leave the previous arm standing and hide every
      // failed-RE-arm bug behind a green suite.
      //
      // AlarmKit is the mirror image: it schedules FIRST and cancels what it
      // superseded afterwards (REVIEW #5), deliberately, so a failed create
      // leaves the OLD alarm armed and named rather than leaving the day
      // silent. `NoEventRing` sets this false. Modelling iOS as destructive
      // was a lie in the direction that hides a ring the engine has stopped
      // tracking.
      if (destructiveOnFailure) scheduled.remove(id);
      return false;
    }
    scheduled[id] = (at: at, volume: volume, title: title, body: body);
    log.add((id: id, at: at));
    return true;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<Set<int>> scheduledIds() async => scheduled.keys.toSet();

  @override
  Future<bool> isRinging(int id) async => ringingIds.contains(id);

  /// True: this fake models the **Android** scheduler, the one platform that
  /// reports host drops. `SilentRing` is the iOS-shaped double (false), and
  /// that difference is what decides whether a vanished ring reads as
  /// `Couldn't confirm` or as an ordinary morning.
  @override
  bool get reportsHostEvents => true;

  @override
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms() async => {
        for (final e in scheduled.entries)
          e.key: ScheduledAlarmInfo(id: e.key, dateTime: e.value.at),
      };

  /// The claim store the bridge uses — exposed so a test can assert an event
  /// was NOT marked handled, which is the whole difference between "deferred
  /// for the next barrier" and "lost".
  final HostAlarmEventClaims hostEventClaims = HostAlarmEventClaims();

  /// **The REAL bridge, not a copy of it.** An earlier version of this fake
  /// reimplemented the queue, the drain and the re-entrancy rules, so the whole
  /// Nivaat matrix proved things about a parallel implementation: the ordering
  /// under test was whatever this file happened to do, and the shipped
  /// bridge — claims, per-event isolation, bounded retry — was exercised by
  /// nothing at all.
  late final HostAlarmEventBridge _bridge = HostAlarmEventBridge(
    events: () => _events.stream,
    claims: hostEventClaims,
  );
  final StreamController<HostAlarmEvent> _events =
      StreamController<HostAlarmEvent>.broadcast();

  @override
  void setHostAlarmEventHandler(
    Future<void> Function(HostAlarmEvent event)? handler,
  ) {
    _bridge.setHandler(handler);
  }

  /// Emit an event the way the plugin does — into the stream, drained by the
  /// bridge — then await the barrier so the test sees a settled world.
  Future<void> emitHostEvent(HostAlarmEvent event) async {
    await _bridge.start();
    _events.add(event);
    await applyHostAlarmEvents();
  }

  @override
  Future<void> applyHostAlarmEvents() => _bridge.apply();
}

/// **The iOS-shaped scheduler:** arms and tracks rings exactly like the Android
/// one, but has no channel to report a move or a drop.
///
/// That single difference is the whole of AlarmKit's position. An alarm leaves
/// AlarmKit the moment it fires and is dismissed, which is indistinguishable
/// from one the host quietly discarded — so an engine that reads "gone" as an
/// anomaly labels every good morning `Couldn't confirm`. Pair it with
/// [FakeRing] to assert the two platforms answer the same story differently.
class NoEventRing extends FakeRing {
  NoEventRing() {
    // AlarmKit schedules before it cancels, so a refused create leaves the
    // superseded alarm armed — the opposite of Android.
    destructiveOnFailure = false;
  }

  @override
  bool get reportsHostEvents => false;
}

/// Answers every other question, but cannot be asked what is armed.
///
/// Models a platform query failing — an AlarmKit `PlatformException`, a Pigeon
/// hiccup — which must never be read as "nothing is armed".
class UnqueryableRing extends FakeRing {
  bool blind = true;

  @override
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms() async {
    if (blind) throw Exception('cannot reach the platform');
    return super.scheduledAlarms();
  }
}

/// Throws Exception on any scheduler touch — guards resync/init soft-fail
/// paths (Errors must still propagate; see controller.resync).
class BoomRing extends FakeRing {
  Never _boom() => throw Exception('scheduler boom');

  @override
  Future<void> cancel(int id) async => _boom();

  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async =>
      _boom();
}

/// Programming Error on any scheduler touch — must NOT be swallowed by resync.
class ErrorRing extends FakeRing {
  Never _boom() => throw StateError('programming boom');

  @override
  Future<void> cancel(int id) async => _boom();

  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async =>
      _boom();
}

/// A scheduler that cannot enumerate what it has armed — the orphan sweep's
/// soft-fail path. Everything else behaves like [FakeRing], so a pass driven
/// through this must still complete and still schedule normally.
class BlindRing extends FakeRing {
  @override
  Future<Set<int>> scheduledIds() async => throw Exception('cannot list ids');
}

/// Lists ids happily but refuses to cancel [refuses] — the sweep's OTHER
/// failure mode, and the one its own `try` originally left uncovered.
///
/// Scoped to specific ids on purpose. A blanket refusal would also break the
/// ordinary cancels inside `_evaluate`, and those have always been allowed to
/// abort their own alarm's pass — `resync` catches it, and [BoomRing] is the
/// test for that. What must NOT happen is the sweep, which runs before the
/// loop, taking every alarm down with it.
class UncancellableRing extends FakeRing {
  UncancellableRing(this.refuses);

  final Set<int> refuses;

  @override
  Future<void> cancel(int id) async {
    if (refuses.contains(id)) throw Exception('cannot cancel $id');
    return super.cancel(id);
  }
}

/// **Deleted with the move to SQLite (2026-08-12).** It modelled the
/// per-isolate SharedPreferences cache — `loadAlarms` answering with the list
/// THIS isolate last saw until `refresh()` pulled in another isolate's writes —
/// and was the only way to prove `_stillLive`'s `store.refresh()` was
/// load-bearing rather than decorative (REVIEW #23).
///
/// There is no per-isolate cache to model any more: a store read is a read of
/// the database file, so a delete the UI isolate committed is simply there.
/// `refresh()` is gone with it. What the test it served now asserts is the half
/// that survives — a pass holding a stale *snapshot* must re-read before it
/// arms — and it needs no fake, because the snapshot is the argument the caller
/// passes in.

/// A wind API that parks its FIRST fetch on a completer, so a test can land a
/// delete inside the exact window a real pass spends waiting on the network.
///
/// That window is the whole of finding #23: `evaluateAll` snapshots the alarm
/// list once and then spends seconds per alarm on a fetch, with the home
/// screen already up — so the user really is deleting alarms while the loop
/// holds a stale copy of them.
class GatedApi extends FakeApi {
  /// Completes once the first fetch is parked — await this before deleting.
  final Completer<void> parked = Completer<void>();

  /// Complete this to let the parked fetch (and every later one) through.
  final Completer<void> gate = Completer<void>();

  bool _open = false;

  Future<void> _park() async {
    if (_open) return;
    _open = true;
    if (!parked.isCompleted) parked.complete();
    await gate.future;
  }

  @override
  Future<WindSample> forecastWindAt(double lat, double lon, DateTime at) async {
    await _park();
    return super.forecastWindAt(lat, lon, at);
  }

  @override
  Future<WindSample> currentWind(double lat, double lon) async {
    await _park();
    return super.currentWind(lat, lon);
  }
}

class FakeChecks implements CheckScheduler {
  final Map<int, DateTime> booked = {};

  /// Whether a booking succeeds. Flip it to drive REVIEW #22: on Android a
  /// refused booking is the end of that alarm's cascade, so the engine must
  /// not carry on as though a wakeup exists.
  bool accepts = true;

  @override
  Future<void> initialize() async {}

  /// Makes [scheduleCheck] THROW rather than decline.
  ///
  /// [accepts] models a booking the platform refuses, which the engine
  /// soft-fails and logs; this models the plugin call itself failing, which
  /// propagates. Every roll-on books a wakeup, so this is the failure point a
  /// roll always reaches — a ring pre-arm is only written near T, so a roll a
  /// day out never gets as far as `scheduleRing`.
  bool throwOnSchedule = false;

  @override
  Future<bool> scheduleCheck(int alarmId, DateTime at) async {
    if (throwOnSchedule) throw Exception('check booking failed');
    if (!accepts) return false;
    booked[alarmId] = at;
    return true;
  }

  @override
  Future<void> cancelCheck(int alarmId) async => booked.remove(alarmId);
}

class FakeApi extends OpenMeteo {
  FakeApi();

  WindSample? sample;
  bool fail = false;
  bool lastCallWasCurrent = false;

  @override
  Future<WindSample> forecastWindAt(double lat, double lon, DateTime target) async {
    lastCallWasCurrent = false;
    if (fail || sample == null) throw OpenMeteoException('down');
    return sample!;
  }

  @override
  Future<WindSample> currentWind(double lat, double lon) async {
    lastCallWasCurrent = true;
    if (fail || sample == null) throw OpenMeteoException('down');
    return sample!;
  }
}

/// A store whose history write always fails. For the single ordering
/// guarantee `NivaatEngine._pushCard` makes: the row is written BEFORE the
/// card, so a failed write leaves nothing in the shade — a card with no record
/// behind it is the one direction the user cannot recover from.
///
/// Throws an `Exception`, not an `Error`, on purpose: the engine wraps only
/// the *notify* half in its `on Exception` guard, and this proves the row half
/// is deliberately left unguarded.
class FailingHistoryStore extends NivaatStore {
  @override
  Future<void> upsertHistory(HistoryRecord record) async =>
      throw Exception('history write failed');
}

/// Records what reached the disk each time the alarm list was written.
///
/// The counter and the alarm that spends it are ONE transaction now (REVIEW
/// #9), so there is no longer an ordering to observe — the question changed
/// from "which landed first" to "did they land together". This watches the pair
/// after each write so a save that advanced one without the other would show.
class SeqWatchingStore extends NivaatStore {
  /// `(counter, alarm ids)` on disk after each [saveAlarms], oldest first.
  final List<(int?, List<int>)> afterEachSave = [];

  @override
  Future<void> saveAlarms(List<NivaatAlarm> alarms, {int? alarmIdSeq}) async {
    await super.saveAlarms(alarms, alarmIdSeq: alarmIdSeq);
    afterEachSave.add((
      await loadAlarmIdSeq(),
      [for (final a in await loadAlarms()) a.id],
    ));
  }
}

WindSample wind(double rawSpeed, double rawGust) => WindSample(
      rawSpeedKmh: rawSpeed,
      rawGustKmh: rawGust,
      observedAt: DateTime(2026, 7, 11),
      isForecast: false,
    );

const court = SavedLocation(id: 'c1', name: 'Home Court', lat: 26.17, lon: 75.79);
// Pin the limit (don't rely on the default) so these wind-decision scenarios
// stay valid if the default changes: raw gust limit 4/0.6*2.2 = 14.667.
const alarm =
    NivaatAlarm(id: 7, hour: 6, minute: 0, courtId: 'c1', courtSpeedLimitKmh: 4);
final alarmAt = DateTime(2026, 7, 12, 6, 0); // 11 Jul 2026 is a Saturday

// Ring lockers are split by ROLE: the pre-arm for an occurrence's own time,
// a LATE ring armed after T, and the pre-arm a roll-on writes for the NEXT
// occurrence. That separation is what stops one pass — which closes an
// occurrence and opens the following one together — from evicting a ring it
// has just armed, or one that is still seconds from sounding.
final todayRing = NivaatIds.ring(alarm.id);
final lateRing = NivaatIds.lateRing(alarm.id);
final nextRing = NivaatIds.nextRing(alarm.id);
