import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_alarmkit/flutter_alarmkit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_pkg_scheduler.dart';
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
  static const String _mapKey = 'alarmkit.idmap';
  bool _authRequested = false;

  @override
  Future<void> ensureInitialized() async {
    if (_authRequested) return;
    final state = await _ak.getAuthorizationState();
    if (state == AlarmAuthorizationState.notDetermined) {
      await _ak.requestAuthorization();
    }
    _authRequested = true;
  }

  /// Reads the id -> UUIDs map from DISK, not from this isolate's cache.
  ///
  /// Without the reload a background isolate never sees what the UI isolate
  /// wrote, so its read-modify-write saves the other side's entries away
  /// (REVIEW #7). This narrows that to the gap between reload and save — there
  /// is still no cross-isolate lock, and SharedPreferences offers none — which
  /// is also why [scheduledIds] only writes when something actually changed.
  ///
  /// **Each id maps to a LIST, newest first** (REVIEW #4 · #5 · #6): the live
  /// UUID plus any whose cancel was not confirmed. One slot per id could not
  /// hold "keep the old handle when its cancel fails" and "create the
  /// replacement before destroying what it replaces" at once — both want it —
  /// so every operation here treats the whole list alike: cancel them all, ask
  /// them all whether one is ringing, prune what AlarmKit has forgotten.
  ///
  /// Only [_saveMap] writes this key, so the shape on disk is always current;
  /// an older build's blob is a cleared-data problem, not a parsing one (see
  /// CLAUDE.md on the no-migration policy).
  Future<Map<String, List<String>>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_mapKey);
    if (raw == null) return {};
    return {
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
        e.key: (e.value as List<dynamic>).cast<String>(),
    };
  }

  /// Persists [map], dropping ids with nothing left in them — an id we hold no
  /// UUID for is an id we know nothing about, and letting an empty list through
  /// would make [scheduledIds] report a handle on no alarm at all.
  Future<void> _saveMap(Map<String, List<String>> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _mapKey,
      jsonEncode({
        for (final e in map.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      }),
    );
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
    // sounding), and a duplicate alert beats a silent morning. CLAUDE.md.
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
      // recorded the alarm as armed, and Nivaat logged `Rang` for a morning
      // that never made a sound (REVIEW #2).
      return false;
    }
    final map = await _loadMap();
    final superseded = map['$id'] ?? const <String>[];
    // Record the new handle BEFORE cancelling anything, so a crash in the gap
    // leaves an alarm we can still name.
    //
    // **The create→save window above is the one leak left, and it cannot be
    // closed here:** AlarmKit mints the UUID, so nothing can be written down
    // until the create returns, and dying in between (iOS killing a background
    // task at expiry) arms an alarm no map names — so nothing can cancel it and
    // it rings even on a morning the wind says to skip. Sweeping alarms this
    // map does not name is the only fix and is NOT a drive-by: in that same
    // window a new alarm looks exactly like an orphan. CLAUDE.md.
    map['$id'] = [uuid, ...superseded];
    await _saveMap(map);
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
    if (gone.isEmpty) return;
    // Re-read: the cancels above took real time, and this entry is a
    // read-modify-write with no cross-isolate lock (REVIEW #7).
    final map = await _loadMap();
    map['$id'] =
        (map['$id'] ?? const <String>[]).where((u) => !gone.contains(u)).toList();
    await _saveMap(map);
  }

  /// The int ids AlarmKit still holds something for.
  ///
  /// **Prunes only what AlarmKit no longer knows AT ALL** (REVIEW #4). Keeping
  /// just `AlarmState.scheduled` dropped the UUID of the alarm sounding right
  /// now, blinding [isRinging] and putting the live alert beyond [cancel].
  /// Every other state is still ours — including `unknown`, which is how a
  /// state a future iOS adds arrives, so pruning on it would wipe the whole map
  /// on the first resync. Nivaat's orphan sweep runs this every pass.
  @override
  Future<Set<int>> scheduledIds() async {
    final map = await _loadMap();
    final Set<String> known;
    try {
      known = {for (final a in await _ak.getAlarms()) a.id};
    } on PlatformException {
      return {};
    }
    var changed = false;
    final kept = <String, List<String>>{};
    for (final e in map.entries) {
      final live = e.value.where(known.contains).toList();
      if (live.length != e.value.length) changed = true;
      if (live.isNotEmpty) kept[e.key] = live;
    }
    // Only write when something actually went. This map is a read-modify-write
    // blob with no cross-isolate lock (REVIEW #7), so every needless save is
    // another chance for two isolates to overwrite each other.
    if (changed) await _saveMap(kept);
    return kept.keys.map(int.parse).toSet();
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
    try {
      final alarms = await _ak.getAlarms();
      for (final a in alarms) {
        if (uuids.contains(a.id) && a.state == AlarmState.alerting) return true;
      }
    } on PlatformException {
      // fall through
    }
    return false;
  }
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
