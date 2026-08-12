import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gives every test in this package a fresh in-memory database.
/// See `packages/core/test/flutter_test_config.dart` for why.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(useInMemoryAppDatabase);
  await testMain();
}
