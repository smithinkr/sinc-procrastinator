# ==========================================================
# 🛡️ S.INC SHIELD: OPTIMIZED PRODUCTION RULES (V3)
# ==========================================================

# 1. GLOBAL STABILITY (Critical for the S23 FE "Restart" Bug)
-dontoptimize
-dontshrink
-keepattributes Signature, *Annotation*, EnclosingMethod

# 2. DART-NATIVE BRIDGE
-keep class io.flutter.embedding.engine.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugin.common.MethodChannel { *; }

# 3. ⚓ THE @PRAGMA ANCHOR (Background Isolate Stability)
-keepclassmembers class * {
    @pragma("vm:entry-point") *;
}
-keep class * {
    @pragma("vm:entry-point") *;
}

# 4. NOTIFICATION & WIDGET ENGINE
# The wildcard covers all receivers and internal notification logic
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.sinc.procrastinator.ProcrastinatorWidgetProvider { *; }
-keep class es.antonborri.home_widget.** { *; }

# 5. S.INC CORE APP LOGIC (Preventing Renaming/Obfuscation)
-keep class com.sinc.procrastinator.MainActivity { *; }
-keep class com.sinc.procrastinator.MyApp { *; }
-keep class com.sinc.procrastinator.AppStartSwitcher { *; }
-keep class com.sinc.procrastinator.AuthGate { *; }
-keep class com.sinc.procrastinator.services.NotificationService { *; }
-keep class com.sinc.procrastinator.services.SettingsService { *; }
-keep class com.sinc.procrastinator.models.Task { *; }

# 6. FIREBASE & IDENTITY (Modern Credential Manager Fix)
-keep class com.google.firebase.** { *; }
-keep interface com.google.firebase.** { *; }
-keep class com.google.android.gms.internal.firebase-auth-api.** { *; }
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.common.api.internal.IStatusCallback { *; }
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.** { *; }