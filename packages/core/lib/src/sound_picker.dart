import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'sounds.dart';
import 'theme.dart';

/// Minimal pitch-black alarm-tone picker: bundled tones plus (on Android)
/// the device's stock alarm sounds, each with tap-to-preview. Returns the
/// chosen option, or null if dismissed.
Future<SoundOption?> showSoundPicker(
  BuildContext context, {
  required String? selectedPath,
}) {
  return showModalBottomSheet<SoundOption>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SoundPickerSheet(selectedPath: selectedPath),
  );
}

class _SoundPickerSheet extends StatefulWidget {
  const _SoundPickerSheet({required this.selectedPath});

  final String? selectedPath;

  @override
  State<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends State<_SoundPickerSheet> {
  final AudioPlayer _player = AudioPlayer();
  List<SoundOption> _system = const [];
  String? _playingPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingPath = null);
    });
    SoundLibrary.systemAlarmSounds().then((sounds) {
      if (mounted) {
        setState(() {
          _system = sounds;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _preview(SoundOption s) async {
    if (_playingPath == s.path) {
      await _player.stop();
      setState(() => _playingPath = null);
      return;
    }
    await _player.stop();
    // AssetSource wants the path without the 'assets/' prefix.
    final source = s.isAsset
        ? AssetSource(s.path.replaceFirst('assets/', ''))
        : DeviceFileSource(s.path);
    await _player.play(source);
    setState(() => _playingPath = s.path);
  }

  Widget _tile(SoundOption s) {
    final selected = s.path == widget.selectedPath;
    final playing = s.path == _playingPath;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: IconButton(
        icon: Icon(
          playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          size: 22,
        ),
        color: playing
            ? Theme.of(context).colorScheme.primary
            : AppPalette.textSecondary,
        onPressed: () => _preview(s),
      ),
      title: Text(s.name),
      trailing: selected
          ? Icon(Icons.check, size: 20,
              color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () => Navigator.of(context).pop(s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SizedBox(
        height: 520,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: ListView(
            children: [
              Text('ALARM SOUND', style: text.labelSmall),
              const SizedBox(height: 8),
              ...SoundLibrary.bundled.map(_tile),
              if (_loading) const LinearProgressIndicator(minHeight: 1),
              if (_system.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('DEVICE ALARM SOUNDS', style: text.labelSmall),
                const SizedBox(height: 8),
                ..._system.map(_tile),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
