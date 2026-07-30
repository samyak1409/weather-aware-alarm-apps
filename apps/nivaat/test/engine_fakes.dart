import 'package:core/core.dart';
import 'package:nivaat/src/check_scheduler.dart';
import 'package:nivaat/src/ids.dart';
import 'package:nivaat/src/skip_notifier.dart';

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
  final Map<int, ({DateTime at, double volume, String title, String body})>
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

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async {
    scheduled[id] = (at: at, volume: volume, title: title, body: body);
    log.add((id: id, at: at));
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
}

/// Throws Exception on any scheduler touch — guards resync/init soft-fail
/// paths (Errors must still propagate; see controller.resync).
class BoomRing extends FakeRing {
  Never _boom() => throw Exception('scheduler boom');

  @override
  Future<void> cancel(int id) async => _boom();

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async =>
      _boom();
}

/// Programming Error on any scheduler touch — must NOT be swallowed by resync.
class ErrorRing extends FakeRing {
  Never _boom() => throw StateError('programming boom');

  @override
  Future<void> cancel(int id) async => _boom();

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async =>
      _boom();
}

class FakeChecks implements CheckScheduler {
  final Map<int, DateTime> booked = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleCheck(int alarmId, DateTime at) async =>
      booked[alarmId] = at;

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

// Ring lockers are split by ROLE: the pre-arm for an occurrence's own time
// vs a LATE ring armed after T. That separation is what stops the next
// occurrence's pre-arm from evicting a late ring.
final todayRing = NivaatIds.ring(alarm.id);
final lateRing = NivaatIds.lateRing(alarm.id);
