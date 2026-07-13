import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled tones are the two shipped assets', () {
    expect(SoundLibrary.bundled.map((s) => s.name),
        containsAll(['Dawn Bells', 'Court Call']));
    expect(SoundLibrary.bundled.every((s) => s.isAsset), isTrue);
  });

  group('displayName', () {
    test('null path returns the provided default', () {
      expect(SoundLibrary.displayName(null, defaultName: 'Dawn Bells'),
          'Dawn Bells');
    });

    test('a bundled asset path maps back to its friendly name', () {
      expect(
        SoundLibrary.displayName('assets/sounds/nivaat_ring.wav',
            defaultName: 'x'),
        'Court Call',
      );
    });

    test('a system file path is prettified from the filename', () {
      expect(
        SoundLibrary.displayName('/system/media/audio/alarms/Cesium_new.ogg',
            defaultName: 'x'),
        'Cesium New',
      );
      // Extensionless basename still prettifies.
      expect(
        SoundLibrary.displayName('/x/alarms/morning-bell', defaultName: 'x'),
        'Morning Bell',
      );
    });
  });

  test('systemAlarmSounds is empty on non-Android hosts', () async {
    // The test host is macOS/Linux, never Android.
    expect(Platform.isAndroid, isFalse);
    expect(await SoundLibrary.systemAlarmSounds(), isEmpty);
  });
}
