import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'courts.dart';
import 'engine.dart';
import 'history_sheet.dart';

/// Nivaat's settings page (2026-07-20). Hosts what used to be the home
/// top-bar trio — alarm sound, courts, history (moved same day; the home bar
/// keeps only this page's tune icon; a live "still checking" home cue is the
/// only home→history shortcut, and only while a retry window is open) — plus
/// the appearance options shared with Arunoday.
///
/// **Courts are a section of this page rather than a tile onto a sheet, and
/// they sit at the END** (2026-08-15, Samyak). Both halves are parity with
/// Arunoday, which has always had LOCATIONS as its last section: the two apps
/// were putting the same thing — the saved places everything else hangs off —
/// in two different shapes at two different ends of the same page. The tile's
/// count went with the sheet; the rows are the count.
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
    return SettingsPage(
      accent: AppPalette.wind,
      children: [
        // The log, then the tone, then appearance, then the courts — the same
        // running order as Arunoday's page, which ends on its saved places
        // too. History leads because it is the row you open this page to READ
        // (2026-08-15, Samyak); the tone is set once.
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('History'),
          trailing: Text('${c.history.length}', style: text.titleMedium),
          onTap: () => showHistorySheet(context, c),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alarm sound'),
          trailing: Text(
            SoundLibrary.displayName(_soundPath, defaultName: 'Court Call'),
            style: text.titleMedium,
          ),
          onTap: _pickSound,
        ),
        const SettingsSection(label: 'APPEARANCE'),
        const HeavyTypeSwitch(),
        const AppIconPicker(
          accent: AppPalette.wind,
          appName: 'Nivaat',
          choices: [
            AppIconChoice(id: '1', label: 'Shuttle', asset: 'assets/icons/1.png'),
            AppIconChoice(id: '2', label: 'Calm', asset: 'assets/icons/2.png'),
            AppIconChoice(id: '3', label: 'Crest', asset: 'assets/icons/3.png'),
          ],
        ),
        SettingsSection(
          label: 'COURTS',
          onAdd: () => pickAndAddCourt(context, c),
          emptyNote: c.courts.isEmpty ? kNivaatNoCourtsYet : null,
        ),
        for (final court in c.courts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(court.name),
            // Three decimals is this app's own resolution, not a convention:
            // 0.001° ≈ 111 m, which is the ~100 m radius N21 refuses
            // duplicates inside (N19).
            subtitle: Text(
              '${court.lat.toStringAsFixed(3)}, '
              '${court.lon.toStringAsFixed(3)}',
              style: text.bodyMedium,
            ),
            trailing: PlaceRowActions(
              place: court,
              accent: AppPalette.wind,
              onDelete: () => confirmAndRemoveCourt(context, c, court),
            ),
          ),
      ],
    );
  }
}
