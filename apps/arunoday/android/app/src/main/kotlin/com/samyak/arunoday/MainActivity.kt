package com.samyak.arunoday

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import com.gdelataillade.alarm.alarm.AlarmService
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

    // Shared with Nivaat's MainActivity — serves core's app_window.dart.
    private val appWindowChannel = "core/app_window"

    // Shared with the other app — serves core's alarm_launch.dart.
    private val alarmLaunchChannel = "core/alarm_launch"

    // The alarm whose ACTION_RING intent brought this activity on screen, or
    // null. Held until Dart pulls it: during onCreate the Dart entrypoint has
    // not run, so there is nobody to push it to (upstream's
    // help/DETECT-ALARM-LAUNCH-ANDROID.md).
    private var alarmLaunchId: Int? = null

    // Whether the activity is currently on screen, tracked across onStart /
    // onStop rather than onResume / onPause: a system dialog over us pauses
    // without hiding, and treating that as "not visible" would read the next
    // alarm as having opened the app.
    private var visible = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A cold start arrives here; `visible` is still false, which is the
        // whole point — this intent is what created us.
        handleAlarmIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Otherwise getIntent() keeps returning the intent that originally
        // created the activity.
        setIntent(intent)
        handleAlarmIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        visible = true
    }

    override fun onStop() {
        super.onStop()
        visible = false
        // An unconsumed token dies with the screen it was about. Once we are
        // off screen the fact "an alarm put us here" is spent whether or not
        // Dart ever read it — and hiding an app that is already hidden is a
        // no-op, so nothing is lost. Without this it outlives its ring: a ring
        // that ended before Dart subscribed leaves the token set, the user
        // comes back through RECENTS (which delivers no Intent at all, so no
        // clearing path involving one can run), and the next ring's stop hides
        // an app they opened.
        alarmLaunchId = null
    }

    /**
     * Records an alarm launch, and ONLY when the alarm is what put us on
     * screen.
     *
     * An ACTION_RING intent reaching an activity that is already visible means
     * the user opened the app first and the alarm arrived afterwards — hiding
     * on stop would then cost them the screen they chose. Not visible covers
     * both cases that should hide: a cold start (onCreate, before the first
     * onStart) and a background app brought forward (onNewIntent after onStop).
     */
    private fun handleAlarmIntent(intent: Intent) {
        if (visible) return
        if (intent.action != AlarmService.ACTION_RING) return
        // Not a trust boundary, and not treated as one: a launcher activity has
        // to be exported, so any app can send us this (upstream says so in its
        // own guidance). The worst it buys is a stray backgrounding.
        val id = intent.getIntExtra(AlarmService.EXTRA_ALARM_ID, -1)
        if (id != -1) alarmLaunchId = id
    }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appWindowChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // A ring the user never asked for is over, so put us
                    // back behind whatever we interrupted - usually the lock
                    // screen, which otherwise shows the app the moment it is
                    // unlocked. Hide, don't finish: the task survives, so
                    // reopening stays warm, and nonRoot = true so it
                    // works even when we are not the task's root activity.
                    // Sync with Nivaat.
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, alarmLaunchChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Reading the field HERE rather than capturing it above is
                    // what makes this safe: configureFlutterEngine runs inside
                    // super.onCreate, before onCreate reaches handleAlarmIntent.
                    // Clearing on read is what "consume" means — the next ring
                    // must not inherit this one's answer. Sync with the other app.
                    "consumeAlarmLaunch" -> {
                        result.success(alarmLaunchId)
                        alarmLaunchId = null
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
