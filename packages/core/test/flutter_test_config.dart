import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gives **every** test in this package a fresh in-memory database.
///
/// `flutter test` runs this file, if present, around the whole suite, so the
/// `setUp` registered here lands on the root group and therefore runs before
/// each test's own. That is the point: the stores resolve `appDb` lazily, and
/// without an override that call reaches `path_provider`, which has no
/// implementation under `flutter test` — so a file that forgot one line would
/// not fail with "you forgot the database", it would fail with a
/// MissingPluginException from a plugin the test never mentioned.
///
/// A test that needs the database itself still calls [useInMemoryAppDatabase]
/// directly, for the handle; calling it again simply replaces this one.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(useInMemoryAppDatabase);
  await testMain();
}
