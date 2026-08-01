package com.samyak.arunoday

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Shared with Nivaat's MainActivity — serves core's
    // openNotificationSettings() (see core/lib/src/system_settings.dart).
    private val settingsChannel = "core/system_settings"

    // Shared with Nivaat's MainActivity — serves core's app_icon.dart.
    // Icon ids "1"/"2"/"3": "1" = MainActivity's own manifest icon (default),
    // "2"/"3" = the .IconTwo/.IconThree activity-aliases. Exactly one
    // launcher component stays enabled; DONT_KILL_APP keeps us alive.
    private val appIconChannel = "core/app_icon"

    private fun iconComponents(): Map<String, ComponentName> = mapOf(
        "1" to ComponentName(this, MainActivity::class.java),
        "2" to ComponentName(this, "$packageName.IconTwo"),
        "3" to ComponentName(this, "$packageName.IconThree"),
    )

    private fun currentIcon(): String {
        val pm = packageManager
        for ((id, component) in iconComponents()) {
            if (id == "1") continue // default state is "no alias enabled"
            if (pm.getComponentEnabledSetting(component) ==
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            ) {
                return id
            }
        }
        return "1"
    }

    // STATE_DEFAULT means "as the manifest declared" — MainActivity ships
    // enabled, both aliases disabled — so the id decides how to read it.
    private fun isIconOn(id: String, component: ComponentName): Boolean =
        when (packageManager.getComponentEnabledSetting(component)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            else -> id == "1"
        }

    private fun setIcon(id: String): Boolean {
        val components = iconComponents()
        val target = components[id] ?: return false
        val pm = packageManager
        // Enable the new launcher entry BEFORE disabling the old one, so the
        // package never has zero launcher components.
        pm.setComponentEnabledSetting(
            target,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for ((otherId, component) in components) {
            if (otherId == id) continue
            // Only one entry is ever on; skipping the no-ops saves binder
            // round-trips the user waits through. Still a loop, so a corrupt
            // two-on state would still resolve.
            if (!isIconOn(otherId, component)) continue
            pm.setComponentEnabledSetting(
                component,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // This app's notification settings page — unreachable by
                    // URL, hence a real intent.
                    "openNotificationSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appIconChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(currentIcon())
                    "set" -> {
                        try {
                            val switched = setIcon(call.argument<String>("id") ?: "")
                            result.success(switched)
                            // Close ourselves rather than wait: Android tears
                            // the task down anyway once the component we were
                            // launched from is disabled, but the beat it takes
                            // reads as a freeze (2026-08-01). Sync with Nivaat.
                            if (switched) finishAndRemoveTask()
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
