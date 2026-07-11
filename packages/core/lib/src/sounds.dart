import 'dart:io';

/// One selectable alarm tone.
class SoundOption {
  const SoundOption({
    required this.name,
    required this.path,
    required this.isAsset,
  });

  final String name;

  /// Flutter asset path ('assets/sounds/x.wav') or absolute device path.
  final String path;
  final bool isAsset;
}

/// Where alarm tones come from:
/// - Bundled: our synthesized tones, shipped in both apps (the only option
///   on iOS — Apple exposes no API to list or use its built-in alarm sounds).
/// - Android system alarm tones: the device's stock alarm sounds live as
///   world-readable files; listing them needs no permission and the `alarm`
///   package plays absolute paths directly.
class SoundLibrary {
  SoundLibrary._();

  static const List<SoundOption> bundled = [
    SoundOption(
      name: 'Dawn Bells',
      path: 'assets/sounds/arunoday_dawn.wav',
      isAsset: true,
    ),
    SoundOption(
      name: 'Court Call',
      path: 'assets/sounds/nivaat_ring.wav',
      isAsset: true,
    ),
  ];

  static const List<String> _systemAlarmDirs = [
    '/product/media/audio/alarms',
    '/system/media/audio/alarms',
    '/system/product/media/audio/alarms',
    '/vendor/media/audio/alarms',
  ];

  static const Set<String> _audioExts = {'.ogg', '.mp3', '.wav', '.m4a'};

  /// Stock alarm tones on Android; empty elsewhere.
  static Future<List<SoundOption>> systemAlarmSounds() async {
    if (!Platform.isAndroid) return const [];
    final out = <SoundOption>[];
    final seen = <String>{};
    for (final dirPath in _systemAlarmDirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final f in dir.list()) {
          if (f is! File) continue;
          final base = f.path.split('/').last;
          final dot = base.lastIndexOf('.');
          if (dot < 0 || !_audioExts.contains(base.substring(dot))) continue;
          final name = _prettify(base.substring(0, dot));
          if (!seen.add(name)) continue;
          out.add(SoundOption(name: name, path: f.path, isAsset: false));
        }
      } on FileSystemException {
        // Some OEM paths are unreadable; skip quietly.
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  static String _prettify(String s) => s
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// Human name for a stored sound path (null = app default).
  static String displayName(String? path, {required String defaultName}) {
    if (path == null) return defaultName;
    for (final b in bundled) {
      if (b.path == path) return b.name;
    }
    final base = path.split('/').last;
    final dot = base.lastIndexOf('.');
    return _prettify(dot > 0 ? base.substring(0, dot) : base);
  }
}
