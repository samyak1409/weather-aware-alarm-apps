/// Courts: the warning that guards a delete, and the two flows that add and
/// remove one.
///
/// **This was a bottom sheet until 2026-08-15** (`courts_sheet.dart`), reached
/// from a `Courts` tile with a count on it. Samyak's read on a device was that
/// it looked older than the rest of the app, and the reason it did is
/// structural rather than cosmetic: it was a sheet inside a sheet's worth of
/// navigation, with its own height cap, its own `ListView`, and a hand-rolled
/// copy of `FlashingScrollbar`'s flash — an inner scroll region on a settings
/// page whose whole design note says it scrolls as ONE surface. Arunoday's
/// LOCATIONS had always been a plain section of its settings page, and that is
/// what COURTS is now. The sheet, its height cap and its scrollbar copy are all
/// gone; what is left here is the parts that were never about the container.
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';

/// Warns what deleting [name] takes with it: its alarms and its history log
/// (both are removed). History only exists once an alarm has fired at least
/// once, so a fresh court names just its alarms (MESSAGES.md N20).
///
/// **Four shapes since 2026-08-15**, because the dialog is now shown for every
/// court rather than only for one with something hanging off it (Samyak). A
/// bare court took one tap to destroy, and the tap that destroys is not the
/// place to decide the user has nothing to lose — they cannot see from the row
/// whether an alarm still points here, which is exactly what the other three
/// shapes exist to tell them. Arunoday's location delete asks on every delete
/// for the same reason.
///
/// **`Deleting {court} also deletes …` — one verb over both nouns** (Samyak,
/// 2026-08-15, on the old `2 alarms use {court} and will be deleted too, along
/// with 5 history entries`). Two rewrites were weighed and both are wrong the
/// same way: `2 alarms and 5 history entries USE Society Court` says history
/// *uses* a court, which it does not — an alarm points at a court, a row is a
/// record of an occurrence that already happened there — and a compound subject
/// then needs a plural verb, so `1 alarm and 1 history entry uses` is
/// ungrammatical on top. Hanging both off `deletes` removes the verb from the
/// argument entirely: nothing has to agree with a count, the trailing
/// afterthought goes, and the sentence leads with the thing you actually did.
/// It also matches Arunoday's `Deleting {name} leaves …` opening.
///
/// Top-level and pure so it can be asserted as a whole string — the same rule
/// `nivaatHistoryLine` / `nivaatHistorySub` moved out for, and for the same
/// reason: this one sat inside the widget and read "**1 alarm use** Society
/// Court" from the day it landed (2026-07-19, `398f5c0`) until a test finally
/// rendered the singular — the better part of a fortnight.
String nivaatDeleteCourtWarning(String name, int alarms, int history) {
  final a = '$alarms ${alarms == 1 ? 'alarm' : 'alarms'}';
  final h = '$history history ${history == 1 ? 'entry' : 'entries'}';
  if (alarms > 0 && history > 0) {
    return 'Deleting $name also deletes $a and $h. Continue?';
  }
  if (alarms > 0) return 'Deleting $name also deletes $a. Continue?';
  if (history > 0) return 'Deleting $name also deletes $h. Continue?';
  // Nothing hangs off it. Saying so is the point: it is the one delete here
  // that really does cost only the court, and the other three shapes are what
  // make that worth stating rather than assuming.
  return 'No alarm uses $name. Continue?';
}

/// What the COURTS section says with nothing in it (MESSAGES.md N19).
///
/// Arunoday's twin is `kArunodayNoLocationsYet`; both follow the same shape —
/// the action, then why you would take it.
const String kNivaatNoCourtsYet =
    'Save your courts — each alarm checks the wind at its own court.';

/// Adds a court through the shared place picker (X5), refusing a same-area
/// duplicate on the way in (N21). Returns whether one was actually saved.
///
/// The return value is what the FAB's bootstrap reads: with no court yet,
/// "add alarm" has to pick a place first and must not open the alarm editor if
/// the user backs out of it.
Future<bool> pickAndAddCourt(BuildContext context, NivaatController c) async {
  final place = await showLocationSearch(context, validate: c.courtRefusal);
  if (place == null || !context.mounted) return false;
  await c.addCourt(place);
  return true;
}

/// Confirms, then removes [court] and everything hanging off it (N20).
///
/// **Every court, including a bare one** (2026-08-15, Samyak). It used to skip
/// the dialog when there were no alarms and no history — "nothing to warn
/// about" — and that reasoning had the decision the wrong way round: the row
/// does not say whether an alarm points here, so the user cannot know which of
/// the four sentences they were about to skip. Arunoday's location delete
/// follows the same rule.
Future<void> confirmAndRemoveCourt(
  BuildContext context,
  NivaatController c,
  SavedLocation court,
) async {
  final ok = await confirmDestructive(
    context,
    title: 'DELETE COURT',
    message: nivaatDeleteCourtWarning(
      court.name,
      c.alarmsForCourt(court.id),
      c.historyForCourt(court.id),
    ),
  );
  if (!ok || !context.mounted) return;
  await c.removeCourt(court.id);
}
