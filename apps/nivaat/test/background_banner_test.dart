import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/background_banner.dart';
import 'package:nivaat/src/battery_optimization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nivaat/battery');

  setUp(() {
    batteryAskInFlight = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      // Background work throttled -> the banner has a reason to show.
      if (call.method == 'isExempt') return false;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    batteryAskInFlight = false;
  });

  Widget host() =>
      const MaterialApp(home: Scaffold(body: BackgroundChecksBanner()));

  testWidgets('shows while background work is throttled', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(NudgeBanner), findsOneWidget);
  });

  testWidgets(
      'suppressed behind the first-run dialog; appears on the resume that '
      'answers it (device-caught flash, 2026-07-20)', (tester) async {
    batteryAskInFlight = true; // the once-ask dialog is (about to be) up
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(NudgeBanner), findsNothing,
        reason: 'never flash behind the very dialog that grants it');

    // The user answers the dialog -> the app resumes.
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(NudgeBanner), findsOneWidget,
        reason: 'denied at the dialog -> the nudge takes over');
    expect(batteryAskInFlight, isFalse);
  });
}
