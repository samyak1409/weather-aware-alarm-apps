/// The active alarm tone. Schedulers capture [arunodaySoundForVolume] at
/// startup and resolve it at every schedule call, so a picker change applies
/// on the next resync without rebuilding schedulers. The controller keeps
/// this in sync with the persisted [ArunodaySettings.soundPath].
library;

const String arunodayDefaultSound = 'assets/sounds/arunoday_dawn.wav';

String? selectedSoundPath;

String arunodaySoundForVolume(double _) =>
    selectedSoundPath ?? arunodayDefaultSound;
