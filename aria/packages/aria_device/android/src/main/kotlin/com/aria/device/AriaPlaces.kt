package com.aria.device

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.CalendarContract
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Location reminders + calendar reading.
 * Geofences: Play services GeofencingClient → [GeofenceReceiver] posts the
 * notification even when Aria isn't running. Specs are kept in
 * SharedPreferences so [GeofenceBootReceiver] can re-register after reboot
 * (Android clears geofences on restart).
 */
object AriaPlaces {
    private const val PREFS = "aria_places"
    private const val KEY = "fences"
    const val REQ_LOCATION = 4101
    const val REQ_BACKGROUND = 4102
    const val REQ_CALENDAR = 4103

    fun has(ctx: Context, p: String) =
        ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED

    fun locationStatus(ctx: Context): String = when {
        !has(ctx, Manifest.permission.ACCESS_FINE_LOCATION) &&
            !has(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) -> "denied"
        Build.VERSION.SDK_INT >= 29 && !has(ctx, Manifest.permission.ACCESS_BACKGROUND_LOCATION) -> "whenInUse"
        else -> "always"
    }

    /** Step 1: foreground location. Step 2 (separate call): background,
     *  which Android 11+ sends to Settings ("Allow all the time"). */
    fun request(activity: Activity, background: Boolean) {
        if (background && Build.VERSION.SDK_INT >= 29) {
            activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQ_BACKGROUND)
        } else {
            activity.requestPermissions(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                REQ_LOCATION,
            )
        }
    }

    @SuppressLint("MissingPermission")
    fun currentLocation(ctx: Context, result: MethodChannel.Result) {
        if (locationStatus(ctx) == "denied") return result.success(null)
        LocationServices.getFusedLocationProviderClient(ctx)
            .getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null)
            .addOnSuccessListener { l ->
                result.success(l?.let { mapOf("lat" to it.latitude, "lng" to it.longitude, "accuracy" to it.accuracy.toDouble()) })
            }
            .addOnFailureListener { result.success(null) }
    }

    private fun pending(ctx: Context): PendingIntent = PendingIntent.getBroadcast(
        ctx, 0, Intent(ctx, GeofenceReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )

    /** Replaces all geofences. Returns how many were registered. */
    fun setGeofences(ctx: Context, fences: List<Map<String, Any?>>, result: MethodChannel.Result?) {
        val json = JSONArray()
        fences.take(90).forEach { json.put(JSONObject(it)) }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json.toString()).apply()
        register(ctx, json) { result?.success(it) }
    }

    @SuppressLint("MissingPermission")
    fun register(ctx: Context, json: JSONArray, done: (Int) -> Unit) {
        val client = LocationServices.getGeofencingClient(ctx)
        client.removeGeofences(pending(ctx)).addOnCompleteListener {
            if (json.length() == 0 || locationStatus(ctx) == "denied") return@addOnCompleteListener done(0)
            val list = (0 until json.length()).map { json.getJSONObject(it) }.map { f ->
                val arrive = f.optString("on", "arrive") == "arrive"
                Geofence.Builder()
                    .setRequestId(f.getString("id"))
                    .setCircularRegion(f.getDouble("lat"), f.getDouble("lng"),
                        f.optDouble("radius", 150.0).coerceIn(100.0, 1000.0).toFloat())
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .setTransitionTypes(if (arrive) Geofence.GEOFENCE_TRANSITION_ENTER else Geofence.GEOFENCE_TRANSITION_EXIT)
                    .build()
            }
            val req = GeofencingRequest.Builder()
                .setInitialTrigger(0) // don't fire for where you already are
                .addGeofences(list).build()
            client.addGeofences(req, pending(ctx))
                .addOnSuccessListener { done(list.size) }
                .addOnFailureListener { done(0) }
        }
    }

    fun reRegister(ctx: Context) {
        val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return
        register(ctx, JSONArray(raw)) {}
    }

    fun spec(ctx: Context, id: String): JSONObject? {
        val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
        val arr = JSONArray(raw)
        return (0 until arr.length()).map { arr.getJSONObject(it) }.firstOrNull { it.getString("id") == id }
    }

    // ------------------------------------------------------------ calendar

    fun calendarStatus(ctx: Context) =
        if (has(ctx, Manifest.permission.READ_CALENDAR)) "granted" else "denied"

    fun calendarEvents(ctx: Context, from: Long, to: Long): List<Map<String, Any?>> {
        if (calendarStatus(ctx) != "granted") return emptyList()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(from.toString()).appendPath(to.toString()).build()
        val cols = arrayOf(
            CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN, CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.EVENT_LOCATION,
        )
        val out = mutableListOf<Map<String, Any?>>()
        ctx.contentResolver.query(uri, cols, null, null, "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext() && out.size < 200) {
                out += mapOf(
                    "id" to "${c.getLong(0)}-${c.getLong(2)}",
                    "title" to (c.getString(1) ?: ""),
                    "start" to c.getLong(2).toDouble(),
                    "end" to c.getLong(3).toDouble(),
                    "allDay" to (c.getInt(4) == 1),
                    "calendar" to (c.getString(5) ?: ""),
                    "location" to (c.getString(6) ?: ""),
                )
            }
        }
        return out
    }
}

/** Geofence crossed → notification that opens the reminder. */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return
        val nm = NotificationManagerCompat.from(ctx)
        if (!nm.areNotificationsEnabled()) return
        for (g in event.triggeringGeofences.orEmpty()) {
            val f = AriaPlaces.spec(ctx, g.requestId) ?: continue
            val open = Intent(Intent.ACTION_VIEW, Uri.parse("aria:///reminder/${g.requestId}"))
                .setPackage(ctx.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val tap = PendingIntent.getActivity(
                ctx, g.requestId.hashCode(), open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val icon = ctx.resources.getIdentifier("ic_notification", "drawable", ctx.packageName)
                .takeIf { it != 0 } ?: ctx.applicationInfo.icon
            val n = NotificationCompat.Builder(ctx, f.optString("channel", "cat_personal"))
                .setSmallIcon(icon)
                .setContentTitle(f.optString("title", "Reminder"))
                .setContentText(f.optString("body", ""))
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(tap)
                .build()
            try {
                nm.notify(f.optInt("notificationId", g.requestId.hashCode()), n)
            } catch (_: SecurityException) {
                // POST_NOTIFICATIONS revoked
            }
        }
    }
}

/** Android forgets geofences on reboot / app update; restore them. */
class GeofenceBootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON" -> AriaPlaces.reRegister(ctx)
        }
    }
}
