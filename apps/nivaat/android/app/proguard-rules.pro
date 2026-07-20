# Flutter release builds enable R8 minify/shrink by default. Without these
# keeps, R8 horizontally merges android_alarm_manager_plus helpers into
# unrelated AndroidX classes (seen: FlutterBackgroundExecutor →
# androidx.lifecycle.ServiceLifecycleDispatcher). That blows up the moment
# main() awaits AndroidAlarmManager.initialize() — "Nivaat keeps stopping"
# on first tap of a release APK. Debug builds don't minify, so flutter run
# never caught it. Arunoday is fine: it doesn't use this plugin.
#
# Keep the whole plugin package (names + members). Manifest components are
# already kept by aapt_rules; this stops the merge that breaks initialize().
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }

# JobIntentService is AlarmService's superclass; keep its inner enqueuers so
# R8 doesn't strip the API-33 JobScheduler path pieces initialize() needs.
-keep class androidx.core.app.JobIntentService { *; }
-keep class androidx.core.app.JobIntentService$* { *; }

# Workmanager ships with Nivaat for iOS BGTasks; its Android plugin still
# registers on every FlutterEngine (including the alarm-manager background
# isolate). Keep it so R8 can't mangle the pigeon host the same way.
-keep class dev.fluttercommunity.workmanager.** { *; }
