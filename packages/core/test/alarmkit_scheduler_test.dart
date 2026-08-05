import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The id -> UUID map is the ONLY handle this app has on an AlarmKit alarm:
/// the plugin assigns the UUIDs, so an entry lost is an alarm that can never be
/// cancelled, asked about, or swept again. These lock the two ways it used to
/// be thrown away (REVIEW #4, #6).
///
/// `AlarmKitScheduler` is listed as a plugin wrapper elsewhere, but the map
/// logic is ours and the plugin talks over a plain MethodChannel — so the
/// decisions here are testable off-device even though the alarms are not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_alarmkit');
  const mapKey = 'alarmkit.idmap';

  late List<MethodCall> calls;
  late List<Map<String, Object?>> alarms; // what AlarmKit reports it holds
  late bool cancelSucceeds;
  late bool cancelThrows;
  late bool scheduleThrows;

  Future<Map<String, String>> savedMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(mapKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    // refuses the cancel or has no mapping to cancel, so map REMOVAL was never
    // executed at all — and the mock's argument shape was wrong underneath it.
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
    // The whole of REVIEW #6. `cancelAlarm` reports failure by RETURNING false
    // as well as by throwing, and the mapping used to be dropped either way —
    // after which nothing could ever name that alarm again.
    final s = scheduler();
    expect(await arm(s, 1), isTrue);
    expect((await savedMap())['1'], isNotNull);

    cancelSucceeds = false;
    await s.cancel(1);

    expect((await savedMap())['1'], isNotNull,
        reason: 'the alarm is still live in AlarmKit, so we must keep its UUID');
  });

  test('a replacement is refused rather than overwriting a live handle',
      () async {
    // The other half, and the one a partial fix misses: `scheduleRing` cancels
    // then writes the new UUID under the same id. With the cancel refused that
    // overwrite loses the old alarm exactly as the old `cancel` did — two live
    // in AlarmKit, one unreachable.
    final s = scheduler();
    await arm(s, 1);
    final original = (await savedMap())['1'];

    cancelSucceeds = false;
    expect(await arm(s, 1), isFalse,
        reason: 'a caller must not be told it armed something');

    expect((await savedMap())['1'], original,
        reason: 'the surviving alarm keeps its handle, so a retry can reach it');
    expect(alarms, hasLength(1), reason: 'and no second alarm was created');
  });

  test('a successful replacement swaps the handle for the new one', () async {
    // The NORMAL iOS path, and it was covered by nothing: every ladder rung
    // that re-decides an occurrence calls scheduleRing again on the same id.
    // The tests around it only ever refused the cancel, so "cancel the old,
    // record the new" — the case that actually runs every morning — was never
    // executed end to end.
    final s = scheduler();
    await arm(s, 1);
    final first = (await savedMap())['1'];

    expect(await arm(s, 1), isTrue);

    final second = (await savedMap())['1'];
    expect(second, isNotNull);
    expect(second, isNot(first), reason: 'the new alarm has its own UUID');
    expect(alarms, hasLength(1),
        reason: 'the old one was cancelled, not left beside it');
    expect(alarms.single['id'], second,
        reason: 'and the surviving alarm is the one we are pointing at');
  });

  test('a channel failure is treated as a refused cancel', () async {
    // The plugin swallows PlatformException itself and returns false, so a
    // platform error reaches us as a value rather than a throw. Either way the
    // rule is the same: unresolved means keep the handle and arm nothing.
    final s = scheduler();
    await arm(s, 1);
    final original = (await savedMap())['1'];

    cancelThrows = true;
    await s.cancel(1);
    expect((await savedMap())['1'], original);
    expect(await arm(s, 1), isFalse);
    expect(alarms, hasLength(1), reason: 'no second alarm was created');
  });

  test('a cancel that works then a schedule that fails leaves nothing behind',
      () async {
    // The last untested corner of the replace path: the old alarm really is
    // gone, and the new one never existed. The map must end up EMPTY — holding
    // the old UUID would point at an alarm AlarmKit no longer has, and holding
    // anything at all would be a handle on nothing.
    final s = scheduler();
    await arm(s, 1);

    scheduleThrows = true;
    expect(await arm(s, 1), isFalse,
        reason: 'nothing was armed, so nothing may be reported as armed');

    expect(alarms, isEmpty, reason: 'the cancel half did succeed');
    expect(await savedMap(), isEmpty,
        reason: 'no alarm exists, so no mapping should claim one');
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
    // The counterweight: keeping everything would leak entries for alarms that
    // really are gone, which is what makes the "keep on failed cancel" rule
    // safe in the first place.
    final s = scheduler();
    await arm(s, 1);
    alarms.clear();

    expect(await s.scheduledIds(), isEmpty);
    expect(await savedMap(), isEmpty);
  });
}
