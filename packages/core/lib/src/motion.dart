import 'package:flutter/scheduler.dart';

/// How much slower than stock both apps animate (1.0 = stock Flutter).
///
/// Experiment (2026-07-20, Samyak; tuned 2026-07-22 to 50%): unhurried
/// motion reads as premium, so every ticker-driven animation — route/sheet
/// transitions, switches, ink ripples — runs 50% slower. One knob so the
/// whole thing is a one-line tune or revert. [timeDilation] is a plain
/// runtime scale read by the scheduler on every frame (no debug-only
/// guard), so this holds in profile/release builds too; it does not change
/// frame RATE, only pacing, so smoothness is untouched.
const double kMotionSlowdown = 1.5;

/// Applies [kMotionSlowdown] app-wide. Call once from `main()`; safe before
/// `runApp` (the setter handles a not-yet-initialized binding).
void applyMotionPacing() {
  timeDilation = kMotionSlowdown;
}
