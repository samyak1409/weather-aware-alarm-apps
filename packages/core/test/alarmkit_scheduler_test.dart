import 'package:core/core.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The id -> UUIDs map is the ONLY handle this app has on an AlarmKit alarm:
/// the plugin assigns the UUIDs, so an entry lost is an alarm that can never be
/// cancelled, asked about, or swept again. These lock the ways it used to be
/// thrown away (REVIEW #4, #6) and the order that stops a failed re-arm from
/// leaving a morning silent (REVIEW #5).
///
/// `AlarmKitScheduler` is listed as a plugin wrapper elsewhere, but the map
/// logic is ours and the plugin talks over a plain MethodChannel — so the
/// decisions here are testable off-device even though the alarms are not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_alarmkit');

  late AppDatabase db;
  late List<MethodCall> calls;
  late List<Map<String, Object?>> alarms; // what AlarmKit reports it holds
  late bool cancelSucceeds;
  late bool cancelThrows;
  late bool scheduleThrows;

  /// The persisted map, rebuilt from the handle rows: a LIST of UUIDs per id,
  /// newest first. One row per handle since 2026-08-12 — the whole-map blob it
  /// replaced was a read-edit-save that two isolates could interleave.
  Future<Map<String, List<String>>> savedMap() async {
    final rows = await (db.select(db.alarmKitHandles)
          ..orderBy([(t) => OrderingTerm.desc(t.seq)]))
        .get();
    final out = <String, List<String>>{};
    for (final row in rows) {
      (out['${row.alarmId}'] ??= <String>[]).add(row.uuid);
    }
    return out;
  }

  setUp(() async {
    db = await useInMemoryAppDatabase();
    calls = [];
    alarms = [];
    cancelSucceeds = true;
    cancelThrows = false;
    scheduleThrows = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getAuthorizationState':
          return 3; // authorized
        case 'requestAuthorization':
          return true;
        case 'scheduleOneShotAlarm':
          // The plugin's own `_rethrowMapped` always rethrows a
          // PlatformException, so this is the shape a real failure arrives in.
          if (scheduleThrows) throw PlatformException(code: 'SCHEDULE_ERROR');
          final uuid = 'uuid-${calls.length}';
          alarms.add({'id': uuid, 'state': 'scheduled'});
          return uuid;
        case 'cancelAlarm':
          if (cancelThrows) {
            throw PlatformException(code: 'CANCEL_ERROR');
          }
          // A BARE STRING, which is what the plugin really sends. It was a map
          // here at first, and no test happened to reach a successful cancel,
          // so the wrong shape sat there passing.
          if (!cancelSucceeds) return false;
          alarms.removeWhere((a) => a['id'] == call.arguments as String);
          return true;
        case 'getAlarms':
          return alarms;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  AlarmKitScheduler scheduler() => AlarmKitScheduler(
        soundAssetForVolume: (_) => 'assets/sounds/ring.wav',
        tintColor: '#FFFFFF',
      );

  Future<bool> arm(AlarmKitScheduler s, int id) => s.scheduleRing(
        id: id,
        at: DateTime(2026, 8, 6, 6),
        title: 't',
        body: 'b',
        volume: null,
      );

  test('a cancel that works removes the mapping', () async {
    // The success path, which nothing reached before: every other test either
    // refuses the cancel or has no mapping to cancel, so map REMOVAL was
    // never executed at all — and the mock's argument shape was wrong
    // underneath it.
    final s = scheduler();
    await arm(s, 1);
    expect((await savedMap())['1'], isNotNull);

    await s.cancel(1);

    expect(await savedMap(), isEmpty,
        reason: 'the alarm is gone, so keeping its UUID would leak the entry');
    expect(alarms, isEmpty);
    expect(calls.map((c) => c.method), contains('cancelAlarm'));
  });

  test('a refused cancel keeps the handle instead of orphaning the alarm',
      () async {
    // The whole of REVIEW #6. `cancelAlarm` reports failure by RETURNING
    // false as well as by throwing, and the mapping used to be dropped either
    // way — after which nothing could ever name that alarm again.
    final s = scheduler();
    expect(await arm(s, 1), isTrue);
    expect((await savedMap())['1'], isNotNull);

    cancelSucceeds = false;
    await s.cancel(1);

    expect((await savedMap())['1'], isNotNull,
        reason:
            'the alarm is still live in AlarmKit, so we must keep its UUID');
  });

  test('a channel failure is treated as a refused cancel', () async {
    // A platform error can arrive as a throw rather than a `false`. Same
    // rule: unresolved means keep the handle.
    final s = scheduler();
    await arm(s, 1);
    final original = (await savedMap())['1'];

    cancelThrows = true;
    await s.cancel(1);

    expect((await savedMap())['1'], original);
    expect(alarms, hasLength(1), reason: 'and the alarm really is still there');
  });

  test('a create that fails leaves the alarm it replaces armed and mapped',
      () async {
    // REVIEW #5, and the reason the order had to change. Cancelling first
    // meant a create that then threw left the day with NO alarm — and
    // nothing on screen to say so, since the caller only learns "not armed".
    // Creating first makes a failure cost nothing at all.
    final s = scheduler();
    await arm(s, 1);
    final original = (await savedMap())['1'];

    scheduleThrows = true;
    expect(await arm(s, 1), isFalse,
        reason: 'nothing new was armed, so nothing may be reported as armed');

    expect(alarms, hasLength(1),
        reason: 'the morning survives: the old alarm was never cancelled');
    expect((await savedMap())['1'], original,
        reason: 'and it is still reachable, so the next rung can retry');
    expect(alarms.single['id'], original!.single);
  });

  test('a successful replacement swaps the handle for the new one', () async {
    // The NORMAL iOS path: every ladder rung that re-decides an occurrence
    // calls scheduleRing again on the same id. It must end with exactly one
    // alarm, and the map pointing at it.
    final s = scheduler();
    await arm(s, 1);
    final first = (await savedMap())['1']!.single;

    expect(await arm(s, 1), isTrue);

    final second = (await savedMap())['1'];
    expect(second, hasLength(1), reason: 'no spare left behind');
    expect(second!.single, isNot(first), reason: 'the new alarm has its own UUID');
    expect(alarms, hasLength(1),
        reason: 'the old one was cancelled, not left beside it');
    expect(alarms.single['id'], second.single,
        reason: 'and the surviving alarm is the one we are pointing at');
  });

  test('a replacement whose cancel is refused keeps BOTH handles', () async {
    // The trade REVIEW #5 accepts, made explicit. With the create first, a
    // refused cancel leaves two live alarms for one id — a duplicate alert,
    // which is a nuisance you can stop, rather than a silent morning. What it
    // must NOT do is lose the older one: one UUID per id overwrote it, and
    // then nothing could ever reach the alarm that was still going to sound.
    final s = scheduler();
    await arm(s, 1);
    final first = (await savedMap())['1']!.single;

    cancelSucceeds = false;
    expect(await arm(s, 1), isTrue,
        reason: 'the new alarm really was created, so say so');

    final held = (await savedMap())['1']!;
    expect(held, hasLength(2), reason: 'both are live, so both stay named');
    expect(held, contains(first));
    expect(alarms, hasLength(2));

    // And the spare is not stranded: the next cancel reaches it.
    cancelSucceeds = true;
    await s.cancel(1);
    expect(alarms, isEmpty);
    expect(await savedMap(), isEmpty);
  });

  test('an older alarm still sounding counts as ringing', () async {
    // Follows from the above: if the refused cancel left the OLD alarm live
    // and that is what the user can hear, `isRinging` must say yes. Reading
    // only the newest UUID would answer no — and Nivaat's Rule 1 would then
    // cancel a ring that is physically going off.
    final s = scheduler();
    await arm(s, 1);
    final first = alarms.single['id'];

    cancelSucceeds = false;
    await arm(s, 1);
    for (final a in alarms) {
      a['state'] = a['id'] == first ? 'alerting' : 'scheduled';
    }

    expect(await s.isRinging(1), isTrue);
  });

  test('an ALERTING alarm keeps its mapping through a sweep', () async {
    // REVIEW #4. `scheduledIds` used to prune every state but `scheduled`, so
    // a sweep during a live ring purged the UUID of the alarm sounding right
    // then — blinding isRinging and making cancel impossible.
    final s = scheduler();
    await arm(s, 1);
    alarms.single['state'] = 'alerting';

    expect(await s.scheduledIds(), {1});
    expect(await s.isRinging(1), isTrue,
        reason: 'the ring we can hear must stay reachable');
  });

  test('an unknown future state is kept, not treated as gone', () async {
    // The plugin maps any state it does not recognise to `unknown` so its API
    // stays forward-compatible. Pruning on that would wipe the entire map on
    // the first resync after an iOS release that adds one.
    final s = scheduler();
    await arm(s, 1);
    alarms.single['state'] = 'something-ios-27-invented';

    expect(await s.scheduledIds(), {1});
  });

  test('a mapping AlarmKit no longer knows about IS pruned', () async {
    // The counterweight: keeping everything would leak entries for alarms
    // that really are gone, which is what makes the "keep on failed cancel"
    // rule safe in the first place.
    final s = scheduler();
    await arm(s, 1);
    alarms.clear();

    expect(await s.scheduledIds(), isEmpty);
    expect(await savedMap(), isEmpty);
  });

  test('pruning is per UUID — a dead spare goes, the live one stays',
      () async {
    // What makes an unresolved cancel a retry rather than a leak: the spare
    // is dropped the moment AlarmKit forgets it (it fired, or a later cancel
    // took), while the alarm still armed under the same id keeps its handle.
    final s = scheduler();
    await arm(s, 1);
    final stale = alarms.single['id'];
    cancelSucceeds = false;
    await arm(s, 1);
    expect((await savedMap())['1'], hasLength(2));

    alarms.removeWhere((a) => a['id'] == stale);
    expect(await s.scheduledIds(), {1});

    final kept = (await savedMap())['1']!;
    expect(kept, hasLength(1));
    expect(kept.single, isNot(stale));
    expect(await s.isRinging(1), isFalse);
  });

  test('pruning never deletes a handle recorded after it looked', () async {
    // `getAlarms()` is a SNAPSHOT. Another isolate arming an alarm in the gap
    // between that snapshot and the DELETE has a brand-new handle that AlarmKit
    // did mention — just not in this answer — so a prune that deletes
    // "everything AlarmKit did not mention" would remove it. The row is then
    // the only handle on an armed alarm, and `cancel`, `isRinging` and the
    // orphan sweep all work off it: the alarm rings on a morning the wind says
    // to skip, and nothing can reach it.
    final s = scheduler();
    await arm(s, 1);
    final existing = (await savedMap())['1']!.single;

    // Arm alarm 2 from "another isolate" DURING the prune: the mock answers
    // getAlarms with the pre-existing alarm only, then a second handle appears
    // before the delete runs.
    var armedDuringPrune = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAlarms') {
        final answer = [
          for (final a in alarms)
            if (a['id'] == existing) a
        ];
        if (!armedDuringPrune) {
          armedDuringPrune = true;
          // AlarmKit knows about it; our snapshot simply predates it.
          alarms.add({'id': 'raced-uuid', 'state': 'scheduled'});
          // Raw SQL because the generated companions are deliberately not
          // exported from `core` — app code must go through the stores.
          await db.customStatement(
            'INSERT INTO alarm_kit_handles (alarm_id, uuid, seq, created_at) '
            'VALUES (2, ?, 1, ?)',
            ['raced-uuid', DateTime.now().microsecondsSinceEpoch],
          );
        }
        return answer;
      }
      return null;
    });

    await s.scheduledIds();

    expect((await savedMap())['2'], ['raced-uuid'],
        reason: 'a handle recorded after the snapshot is not this prune\'s to '
            'delete');
    expect((await savedMap())['1'], [existing]);
  });

  test('one id\'s handles are untouched by another id\'s writes', () async {
    // The reason this is rows rather than one blob. The prefs map was a
    // read-edit-save over EVERY id at once, so a background isolate writing
    // alarm 2's entry saved alarm 1's away with it (REVIEW #7) — reloading
    // first narrowed that window and could not close it, because prefs has no
    // compare-and-swap. Now a write names its own rows and nothing else can be
    // caught by it.
    final s = scheduler();
    await arm(s, 1);
    final first = (await savedMap())['1'];
    await arm(s, 2);
    // A refused cancel on 2 forces a second handle under it — the write that
    // used to rewrite the whole map.
    cancelSucceeds = false;
    await arm(s, 2);

    expect((await savedMap())['2'], hasLength(2));
    expect((await savedMap())['1'], first,
        reason: 'alarm 1 was never mentioned by any of that');
  });
}
