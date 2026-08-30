import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hidden developer settings, unlocked the way Android unlocks its own
/// (2026-08-06, Samyak): seven taps on the maker's mark at the foot of either
/// home screen turn them on and say so, the next seven turn them off again.
///
/// **What it gates today is one value on three rows** — Nivaat's 15-minute
/// segment, offered on *Keep checking*, *Time until you play* and *Minimum
/// play time* alike (`kDevMinutesOption`, which carries why 15 and why one
/// value), so a whole occurrence can be played out inside an hour while
/// testing. It is not a choice a real user has reason to make: fifteen minutes
/// is one retry and one play slot. It is written as a switch rather than as
/// that one option because more will hang off it.
///
/// **Both apps share the gesture even though Arunoday has nothing behind it
/// yet** — the way in should be the same in both, and a gate that only exists
/// in the app that currently needs it is a gate that gets re-invented.
class DevMode {
  DevMode._();

  static const _key = 'dev.enabled';

  /// Taps that flip the switch — Android's own number, for the same reason:
  /// enough that nobody arrives here by accident.
  static const int tapsToToggle = 7;

  /// How long a run of taps may pause before it is forgotten. The mark is on
  /// screen all day, so without a window a stray tap now and then would
  /// eventually add up to seven and flip the switch with nobody meaning to.
  ///
  /// **One second (Samyak, 2026-08-06, down from two.)** Deliberate taps land
  /// 150-300 ms apart, so a second is already several times the room anyone
  /// needs, and every millisecond past that is only more window for strays to
  /// accumulate in. Don't widen it to fix a "the taps don't register" report
  /// — seven taps in seven seconds was never the failing case.
  static const Duration tapGap = Duration(seconds: 1);

  /// Live, so anything behind the gate rebuilds the moment it flips
  /// (Nivaat's editor listens; see `minuteOptionsFor`).
  static final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// Call once from `main()` before `runApp`, beside `Appearance.load()`.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// The toast (MESSAGES.md X8). Says which way the switch went, because the
/// gesture gives no other feedback — and a hidden switch you can't tell the
/// state of is worse than no switch.
const String kDevModeOnMessage = 'Developer settings enabled';
const String kDevModeOffMessage = 'Developer settings disabled';

/// Counts one run of taps towards [DevMode.tapsToToggle].
///
/// Pure and time-injected so its two rules can be tested without waiting on a
/// real clock: a run that pauses longer than [DevMode.tapGap] starts over, and
/// every seventh tap of one flips the switch, so the next seven flip it back.
class DevTapRun {
  int _taps = 0;
  DateTime? _last;

  /// How many taps the live run stands at — 1 on the tap that opens one, and
  /// climbing for as long as the drumming keeps up.
  ///
  /// Read by the maker's mark to tell the two things a tap on SAMYAK can be
  /// apart: at 1 it is a link being followed, past 1 it is the gate being
  /// worked (see `CraftedBy.linkDelay`). A pause is the only thing that ever
  /// puts it back to 1 — see [tap].
  int get taps => _taps;

  /// Records a tap at [now]. True when this tap completes a run of
  /// [DevMode.tapsToToggle].
  ///
  /// A gap of exactly [DevMode.tapGap] still continues the run — the boundary
  /// has to fall somewhere, and a failed unlock costs one more tap.
  ///
  /// **An unlock happens INSIDE a run rather than ending one** (Samyak,
  /// 2026-08-20): every seventh tap flips the switch and nothing is reset.
  /// Zeroing the count was the same thing until the mark began READING it,
  /// and then it made the eighth tap of an unlock look exactly like a lone
  /// first tap — so the site opened behind the toast that had just said
  /// developer settings were on. A thumb does not stop dead on the seventh.
  bool tap(DateTime now) {
    final last = _last;
    _taps =
        last == null || now.difference(last) > DevMode.tapGap ? 1 : _taps + 1;
    _last = now;
    return _taps % DevMode.tapsToToggle == 0;
  }
}
