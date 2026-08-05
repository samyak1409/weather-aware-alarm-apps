import 'dart:async';
import 'dart:io';

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

/// Answers each query after its own delay, so replies land out of order —
/// the only way to reproduce REVIEW #17.
class _OutOfOrderGeocode extends OpenMeteo {
  _OutOfOrderGeocode(this.delays);
  final Map<String, Duration> delays;
  final List<String> asked = [];

  @override
  Future<List<GeoPlace>> geocode(String query) async {
    asked.add(query);
    await Future<void>.delayed(delays[query] ?? Duration.zero);
    return [GeoPlace(name: 'result:$query', region: 'r', lat: 1, lon: 2)];
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

  testWidgets('an empty field disables Save instead of restoring the default',
      (tester) async {
    // 2026-07-31: clearing the field used to silently re-substitute
    // `My location` on Save. Whitespace counts as empty — Save is driven by
    // the trimmed value, the same value it would have written.
    String? saved;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            saved = await showNamePlaceDialogForTest(context);
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('NAME THIS PLACE'), findsOneWidget, reason: 'X5 title');
    expect(find.text('My location'), findsOneWidget,
        reason: 'X5 default, pre-filled in the field');

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save')).onPressed,
        isNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(closed, isFalse, reason: 'a dead Save leaves the dialog open');

    // Keyboard submit must not be the back door round the disabled button.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(closed, isFalse);

    // Type something and Save comes back.
    await tester.enterText(find.byType(TextField), 'Home');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 'Home');
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

  /// Opens the search sheet with [api] and returns once it is up.
  Future<void> openSearch(WidgetTester tester, OpenMeteo api) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              unawaited(showLocationSearchForTest(context, api: api)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a slow older search never lands on a newer one (REVIEW #17)',
      (tester) async {
    // The debounce cancels a pending timer, never a request already sent, so
    // the field said Tokyo above a list of Toronto — and tapping a row saved
    // the wrong place.
    final api = _OutOfOrderGeocode({'To': const Duration(milliseconds: 500)});
    await openSearch(tester, api);

    await tester.enterText(find.byType(TextField), 'To');
    await tester.pump(const Duration(milliseconds: 400)); // 'To' is sent
    await tester.enterText(find.byType(TextField), 'Tokyo');
    await tester.pump(const Duration(milliseconds: 400)); // 'Tokyo' is sent
    await tester.pump(); // and answers straight away
    expect(find.text('result:Tokyo'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600)); // 'To' finally lands
    expect(api.asked, ['To', 'Tokyo'],
        reason: 'both really were in flight — otherwise this proves nothing');
    expect(find.text('result:Tokyo'), findsOneWidget);
    expect(find.text('result:To'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing the field drops the reply already in flight',
      (tester) async {
    // The other direction: delete what you typed and the list must stay empty
    // rather than filling in behind you.
    final api = _OutOfOrderGeocode({'Tokyo': const Duration(milliseconds: 500)});
    await openSearch(tester, api);

    await tester.enterText(find.byType(TextField), 'Tokyo');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'nothing is loading for a query that no longer exists');

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('result:Tokyo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the GPS path never reaches for a cached position (REVIEW #18)', () {
    // Read off the source, because the rule is an ABSENCE and no widget test
    // can assert one. A live fix or nothing — an age limit was tried and
    // rejected (Samyak, 2026-08-05): a cached fix is a guess about where you
    // are whatever its timestamp says, and this coordinate is saved once and
    // then trusted by every alarm it feeds.
    final source = File('lib/src/location_picker.dart').readAsStringSync();
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code, isNot(contains('getLastKnownPosition')));
  });
}
