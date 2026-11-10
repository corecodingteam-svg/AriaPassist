package com.aria.device

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

/** Ringer mode + native TTS, usable from background isolates (alarm callbacks). */
class AriaDevicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var current: TextToSpeech? = null
    private var activity: ActivityPluginBinding? = null
    private val pendingPermission = mutableMapOf<Int, MutableList<MethodChannel.Result>>()

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, grants: IntArray): Boolean {
        val waiting = pendingPermission.remove(code) ?: return false
        val value = if (code == AriaPlaces.REQ_CALENDAR) AriaPlaces.calendarStatus(context)
            else AriaPlaces.locationStatus(context)
        waiting.forEach { it.success(value) }
        return true
    }

    private fun askPermission(code: Int, result: MethodChannel.Result, ask: (android.app.Activity) -> Unit) {
        val a = activity?.activity
        if (a == null) {
            result.success(if (code == AriaPlaces.REQ_CALENDAR) AriaPlaces.calendarStatus(context) else AriaPlaces.locationStatus(context))
            return
        }
        pendingPermission.getOrPut(code) { mutableListOf() }.add(result)
        ask(a)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.aria/device")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ringerMode" -> {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                result.success(
                    when (am.ringerMode) {
                        AudioManager.RINGER_MODE_SILENT -> "silent"
                        AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                        else -> "normal"
                    }
                )
            }
            "speak" -> speak(call, result)
            "manufacturer" -> result.success(android.os.Build.MANUFACTURER.lowercase())
            "isIgnoringBatteryOptimizations" -> {
                val pm = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
            }
            "requestIgnoreBatteryOptimizations" -> {
                // Shows the system "Let app always run in background?" dialog.
                result.success(
                    start(
                        Intent(
                            android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            android.net.Uri.parse("package:${context.packageName}")
                        )
                    ) || start(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                )
            }
            "openAutoStartSettings" -> result.success(openAutoStart())
            "openAppSettings" -> result.success(
                start(
                    Intent(
                        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.parse("package:${context.packageName}")
                    )
                )
            )
            "locationPermission" -> result.success(AriaPlaces.locationStatus(context))
            "requestLocationPermission" -> {
                val background = call.argument<Boolean>("background") ?: false
                val code = if (background) AriaPlaces.REQ_BACKGROUND else AriaPlaces.REQ_LOCATION
                askPermission(code, result) { AriaPlaces.request(it, background) }
            }
            "currentLocation" -> AriaPlaces.currentLocation(context, result)
            "setGeofences" -> {
                @Suppress("UNCHECKED_CAST")
                val fences = call.argument<List<Map<String, Any?>>>("fences") ?: emptyList()
                AriaPlaces.setGeofences(context, fences, result)
            }
            "calendarPermission" -> result.success(AriaPlaces.calendarStatus(context))
            "requestCalendarPermission" -> askPermission(AriaPlaces.REQ_CALENDAR, result) {
                it.requestPermissions(arrayOf(android.Manifest.permission.READ_CALENDAR), AriaPlaces.REQ_CALENDAR)
            }
            "calendarEvents" -> {
                val from = (call.argument<Number>("from") ?: 0).toLong()
                val to = (call.argument<Number>("to") ?: 0).toLong()
                Thread { val ev = AriaPlaces.calendarEvents(context, from, to); main.post { result.success(ev) } }.start()
            }
            "stop" -> {
                current?.stop()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    /**
     * Best effort: OEM "autostart"/"background activity" screens that kill
     * reminders on Xiaomi, Oppo, Vivo, Samsung, OnePlus, Huawei. Falls back
     * to the app's settings page.
     */
    private fun openAutoStart(): Boolean {
        val candidates = listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        )
        for ((pkg, cls) in candidates) {
            if (start(Intent().setComponent(android.content.ComponentName(pkg, cls)))) return true
        }
        return start(
            Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:${context.packageName}")
            )
        )
    }

    private fun speak(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: return result.success(false)
        val locale = call.argument<String>("locale") ?: "en-IN"
        val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
        val pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat()
        val alarm = call.argument<Boolean>("alarmStream") ?: false

        var tts: TextToSpeech? = null
        var done = false
        fun finish(ok: Boolean) {
            main.post {
                if (!done) {
                    done = true
                    tts?.shutdown()
                    result.success(ok)
                }
            }
        }
        // Never hang the caller (e.g. no TTS engine installed).
        main.postDelayed({ finish(false) }, 30_000)

        tts = TextToSpeech(context) { status ->
            val engine = tts
            current = engine
            if (status != TextToSpeech.SUCCESS || engine == null) {
                finish(false)
                return@TextToSpeech
            }
            engine.language = Locale.forLanguageTag(locale)
            engine.setSpeechRate(rate)
            engine.setPitch(pitch)
            engine.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(if (alarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {}
                override fun onDone(id: String?) {
                    finish(true)
                }

                @Deprecated("Deprecated in API")
                override fun onError(id: String?) {
                    finish(false)
                }
            })
            val params = Bundle()
            params.putInt(
                TextToSpeech.Engine.KEY_PARAM_STREAM,
                if (alarm) AudioManager.STREAM_ALARM else AudioManager.STREAM_NOTIFICATION
            )
            if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, UUID.randomUUID().toString()) != TextToSpeech.SUCCESS) {
                finish(false)
            }
        }
    }
}
