import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the OS settings pages the nudge banners point at. iOS reaches
/// everything through the app's own Settings page (`app-settings:`); Android's
/// notification page needs a real intent, served by a tiny MethodChannel that
/// BOTH apps' MainActivities implement (core is app-agnostic, so the channel
/// name is shared — keep the Kotlin handlers in sync with it).
const MethodChannel _settingsChannel = MethodChannel('core/system_settings');

/// This app's notification settings (Android) / Settings page (iOS).
Future<void> openNotificationSettings() async {
  if (Platform.isAndroid) {
    try {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
    } on PlatformException {
      // No handler / no settings activity — nothing more we can do.
    } on MissingPluginException {
      // Host app forgot the channel; never crash a nudge.
    }
  } else {
    await openIosAppSettings();
  }
}

/// The app's Settings page on iOS — notification toggles, Background App
/// Refresh, and the AlarmKit permission all live there.
Future<void> openIosAppSettings() async {
  await launchUrl(Uri.parse('app-settings:'));
}
