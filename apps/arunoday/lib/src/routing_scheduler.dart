import 'package:core/core.dart';

/// Routes Arunoday's alarms to the best engine per alarm type:
/// - wake alarms (ids 1000-1999) -> platform scheduler (AlarmKit on iOS 26:
///   Silent/Focus-proof, survives termination — the one that MUST ring);
/// - bedtime alarms (ids 2000-2999) -> `alarm` package, so the in-app
///   bedtime-ritual ring screen (delay / tomorrow-offset) keeps working.
///   You're awake at bedtime, so notification-grade reliability is fine.
///
/// On Android both routes are the same `alarm`-package instance.
class RoutingScheduler implements AlarmScheduler {
  RoutingScheduler({required this.wake, required this.bedtime});

  final AlarmScheduler wake;
  final AlarmScheduler bedtime;

  AlarmScheduler _route(int id) =>
      (id >= 2000 && id < 3000) ? bedtime : wake;

  bool get _sameInstance => identical(wake, bedtime);

  @override
  Future<void> ensureInitialized() async {
    await wake.ensureInitialized();
    if (!_sameInstance) await bedtime.ensureInitialized();
  }

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) =>
      _route(id).scheduleRing(
          id: id, at: at, title: title, body: body, volume: volume);

  @override
  Future<void> cancel(int id) => _route(id).cancel(id);

  @override
  Future<Set<int>> scheduledIds() async {
    final ids = await wake.scheduledIds();
    if (_sameInstance) return ids;
    return {...ids, ...await bedtime.scheduledIds()};
  }

  @override
  Future<bool> isRinging(int id) => _route(id).isRinging(id);
}
