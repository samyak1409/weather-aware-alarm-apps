import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';

// Used by the generated part, which inherits this file's imports rather than
// `tables.dart`'s: the enums behind every `textEnum` column live there.
import '../models.dart';
import '../repos.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The one SQLite database both apps' contended state lives in.
///
/// **Why SQLite at all — and it is not "prefs is slow".** The problem is
/// cross-isolate atomicity. SharedPreferences has no compare-and-swap, so
/// every read-modify-write in this repo is a check-then-act two isolates can
/// interleave, and three review rounds closed findings of exactly that shape by
/// *narrowing* the window rather than removing it. A wind check firing while
/// the app is open at 06:00 is the DESIGNED case, not a corner.
///
/// **The database does not fix that by itself.** SQLite hands you a
/// transaction; if the racing read-modify-writes don't go inside one you have
/// gained a dependency and nothing else.
///
/// **Each isolate opens its own connection to the same file** — no host
/// connection, no `computeWithDatabase`. Drift's built-in threading routes
/// every isolate through one host connection, and in Nivaat's background-only
/// wake there is no host isolate running to route through. Plain
/// [NativeDatabase] per isolate plus WAL lets SQLite's own file locking make
/// `BEGIN IMMEDIATE` atomic across processes, which is the model that fits.
@DriftDatabase(
  tables: [
    Courts,
    NivaatAlarms,
    Counters,
    HistoryEntries,
    CheckStates,
    PendingRings,
    HostEventClaims,
    AlarmKitHandles,
    OutboxEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// **1, and there is no upgrade path — by policy, not by omission.** Neither
  /// app has shipped and clearing app data is the upgrade path (CLAUDE.md), so
  /// the first build with this database simply creates its tables and ignores
  /// whatever is in prefs. **Do not write a prefs -> SQLite importer**: that is
  /// exactly the "fallback to make a parser safe" the no-migration policy
  /// forbids, and it would carry forward blobs written by builds whose bugs are
  /// the reason for this change. When shipping starts, that policy changes
  /// first and deliberately, and drift's migrations take over from here.
  @override
  int get schemaVersion => 1;
}

/// Opens the app's database file with the pragmas this design depends on.
///
/// WAL is the load-bearing one: it lets a reader and a writer hold the file at
/// once, which is the whole point when a background wind check and the open app
/// are both awake. `busy_timeout` is the other half — without it a second
/// isolate meeting a held write lock fails instantly with `SQLITE_BUSY` instead
/// of waiting the moment out.
///
/// **The file needs no special protection class on iOS, and that is settled
/// rather than assumed.** App-container files default to
/// `NSFileProtectionCompleteUntilFirstUserAuthentication`, and Apple guarantees
/// a background task is not started before the first unlock ("we won't start
/// your task until the user first unlocks their device", WWDC19 707), so the
/// case where a background isolate cannot open the file never arises. Take the
/// default.
QueryExecutor openAppDatabase() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/app.sqlite');
    return NativeDatabase(file, setup: _applyPragmas);
  });
}

void _applyPragmas(CommonDatabase db) {
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA busy_timeout = 5000');
  // Off by default in SQLite and needed for the `ON DELETE` behaviour any
  // future relation would rely on; cheap, and easy to forget once tables exist.
  db.execute('PRAGMA foreign_keys = ON');
}

AppDatabase? _instance;

/// This isolate's connection.
///
/// Deliberately per-isolate and lazy: a background wake opens its own
/// connection to the same file, which is what makes SQLite's locking — rather
/// than any Dart-side coordination — the thing that serialises the writes.
AppDatabase get appDb => _instance ??= AppDatabase(openAppDatabase());

/// Point every store at a fresh in-memory database for one test.
///
/// Call it from `setUp`, exactly where a test already calls
/// `SharedPreferences.setMockInitialValues({})`. It closes whatever the
/// previous test left behind rather than asking for a teardown, so there is
/// nothing to forget and no ordering to get wrong; the last test's database is
/// released when the process exits.
///
/// Returns the database so a test can reach the tables directly.
///
/// In-memory means ONE connection, so this exercises the transactions but
/// **not** the cross-isolate contention they exist for — proving that needs two
/// real isolates over one file, which is a device concern.
@visibleForTesting
Future<AppDatabase> useInMemoryAppDatabase() async {
  // Awaited rather than fire-and-forget: drift warns loudly when a second
  // database is constructed while the first is still open, and every test's
  // setUp would otherwise trip it.
  await _instance?.close();
  return _instance = AppDatabase(NativeDatabase.memory(setup: _applyPragmas));
}
