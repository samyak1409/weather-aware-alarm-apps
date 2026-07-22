import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'courts_sheet.dart';
import 'engine.dart';
import 'history_sheet.dart';

/// Nivaat's settings page (2026-07-20). Hosts what used to be the home
/// top-bar trio — alarm sound, courts, history (moved same day; the home bar
/// keeps only this page's tune icon; a live "still checking" home cue is the
/// only home→history shortcut, and only while the +30m window is open) — plus
/// the appearance options shared with Arunoday.
void showSettingsSheet(BuildContext context, NivaatController c) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => _SettingsPage(c: c)),
  );
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({required this.c});

  final NivaatController c;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  NivaatController get c => widget.c;

  /// The stored tone path (null = default), for the trailing label.
  String? _soundPath;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    c.store.loadSoundPath().then((p) {
      if (mounted) setState(() => _soundPath = p);
    });
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickSound() async {
    final picked = await showSoundPicker(context,
        selectedPath: _soundPath ?? nivaatDefaultSound);
    if (picked == null) return;
    await c.store.saveSoundPath(picked.path);
    nivaatSelectedSound = picked.path;
    if (mounted) setState(() => _soundPath = picked.path);
    await c.resync();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('SETTINGS', style: text.labelSmall)),
      body: SafeArea(
        top: false,
        // Whole-page scroll, like Arunoday's settings (2026-07-20).
        child: FlashingScrollbar(
          builder: (scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              // Configure → observe → decorate: courts (the domain setup)
              // first, the tone, then the log, then appearance.
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Courts'),
                trailing: Text('${c.courts.length}', style: text.titleMedium),
                onTap: () => showCourtsSheet(context, c),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Alarm sound'),
                trailing: Text(
                  SoundLibrary.displayName(_soundPath,
                      defaultName: 'Court Call'),
                  style: text.titleMedium,
                ),
                onTap: _pickSound,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('History'),
                trailing: Text('${c.history.length}', style: text.titleMedium),
                onTap: () => showHistorySheet(context, c),
              ),
              const SizedBox(height: 4),
              const Divider(),
              const SizedBox(height: 8),
              Text('APPEARANCE', style: text.labelSmall),
              const HeavyTypeSwitch(),
              const AppIconPicker(
                accent: AppPalette.wind,
                choices: [
                  AppIconChoice(
                      id: '1', label: 'Shuttle', asset: 'assets/icons/1.png'),
                  AppIconChoice(
                      id: '2', label: 'Calm', asset: 'assets/icons/2.png'),
                  AppIconChoice(
                      id: '3', label: 'Crest', asset: 'assets/icons/3.png'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
