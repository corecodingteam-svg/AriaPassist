# flutter_local_notifications persists scheduled notifications with Gson
# (needed to restore them after reboot).
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
# Geofence / boot receivers are referenced from the manifest.
-keep class com.aria.device.** { *; }
-keep class com.aria.pa.** { *; }
