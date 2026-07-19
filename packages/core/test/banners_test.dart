import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('NotificationPermissionBanner shows only when denied',
      (tester) async {
    await tester.pumpWidget(host(NotificationPermissionBanner(
      message: 'Notifications are off',
      accent: Colors.blue,
      denied: () async => true,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Notifications are off'), findsOneWidget);
    expect(find.text('Turn on notifications'), findsOneWidget);
  });

  testWidgets('NotificationPermissionBanner stays hidden while granted/unasked',
      (tester) async {
    await tester.pumpWidget(host(NotificationPermissionBanner(
      message: 'Notifications are off',
      accent: Colors.blue,
      denied: () async => false,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Notifications are off'), findsNothing);
  });

  testWidgets('recheckAfter completion re-checks (deny at the startup prompt)',
      (tester) async {
    // Mount while the first-run dialog is notionally still open: undetermined,
    // so no banner. The user answers "don't allow" -> the request future
    // completes -> the banner re-checks and appears without a resume.
    var denied = false;
    final prompt = Completer<void>();
    await tester.pumpWidget(host(NotificationPermissionBanner(
      message: 'Notifications are off',
      accent: Colors.blue,
      denied: () async => denied,
      recheckAfter: prompt.future,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Notifications are off'), findsNothing);

    denied = true;
    prompt.complete();
    await tester.pumpAndSettle();
    expect(find.text('Notifications are off'), findsOneWidget);
  });

  testWidgets('NudgeBanner fires its action on tap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(host(NudgeBanner(
      message: 'Something is off',
      actionLabel: 'Fix it',
      accent: Colors.blue,
      onAction: () => tapped++,
    )));
    await tester.tap(find.text('Fix it'));
    expect(tapped, 1);
  });
}
