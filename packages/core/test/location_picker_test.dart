import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowGeocode extends OpenMeteo {
  _ThrowGeocode(this._error);
  final Object _error;

  @override
  Future<List<GeoPlace>> geocode(String query) async {
    // ignore: only_throw_errors — test seam for Exception vs Error paths
    throw _error;
  }
}

void main() {
  test('locationSearchErrorMessage maps Exceptions only', () {
    expect(
      locationSearchErrorMessage(OpenMeteoException('down')),
      'Search failed — check network',
    );
    expect(locationSearchErrorMessage(Exception('x')),
        'Search failed — check network');
    expect(locationSearchErrorMessage(StateError('bug')), isNull);
  });

  test('reportLocationSearchFailure shows Exception message', () {
    String? shown;
    reportLocationSearchFailure(
      OpenMeteoException('down'),
      (m) => shown = m,
    );
    expect(shown, 'Search failed — check network');
  });

  test('reportLocationSearchFailure rethrows Errors without showing', () {
    var shown = false;
    expect(
      () => reportLocationSearchFailure(StateError('bug'), (_) {
        shown = true;
      }),
      throwsStateError,
    );
    expect(shown, isFalse);
  });

  test('reportLocationSearchFailure preserves stackTrace on rethrow', () {
    final st = StackTrace.current;
    try {
      reportLocationSearchFailure(
        StateError('bug'),
        (_) {},
        stackTrace: st,
      );
      fail('expected throw');
    } catch (e, caught) {
      expect(e, isA<StateError>());
      expect(caught, same(st));
    }
  });

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

  testWidgets('geocode Exception shows Search failed message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            unawaited(showLocationSearchForTest(
              context,
              api: _ThrowGeocode(OpenMeteoException('down')),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ja');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(); // geocode Future completes

    expect(find.text('Search failed — check network'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
