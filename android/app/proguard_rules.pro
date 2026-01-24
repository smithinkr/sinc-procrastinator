# ==========================================================
# 🛡️ S.INC SHIELD: THE PROCRASTINATOR PRODUCTION RULES (V2)
# ==========================================================

# 1. STOP THE SHREDDER (Stability over size)
-dontoptimize
-dontshrink

# 2. PROTECT THE DART-NATIVE BRIDGE
# This keeps the "IST Handshake" alive
-keep class io.flutter.embedding.engine.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugin.common.MethodChannel { *; }

# 3. ⚓ THE @PRAGMA ANCHOR (Essential for Background Isolate)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes EnclosingMethod
-keepclassmembers class * {
    @pragma("vm:entry-point") *;
}
-keep class * {
    @pragma("vm:entry-point") *;
}

# 4. NOTIFICATION ENGINE PROTECTION
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver { *; }

# 5. PROTECT YOUR SERVICE CLASSES
# If NotificationService is renamed, the background callback fails.
-keep class com.sinc.procrastinator.services.NotificationService { *; }
-keep class com.sinc.procrastinator.models.Task { *; }

# 6. WIDGET & HOME PLUGIN (S.INC Specifics)
-keep class com.sinc.procrastinator.ProcrastinatorWidgetProvider { *; }
-keep class es.antonborri.home_widget.** { *; }