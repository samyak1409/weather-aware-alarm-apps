import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fast Save on GPS name dialog does not dispose controller early',
      (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            saved = await showNamePlaceDialogForTest(context);
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Default name, immediate Save — reproduces the fast-tap race from logs.
    await tester.tap(find.text('Save'));
    await tester.pump(); // dialog route popping; old bug fired here
    await tester.pumpAndSettle();

    expect(saved, 'My location');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save with empty field falls back to default name', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            saved = await showNamePlaceDialogForTest(context);
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, 'My location');
  });

  testWidgets('keyboard submit saves the typed name', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            saved = await showNamePlaceDialogForTest(context);
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Home');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(saved, 'Home');
  });
}
