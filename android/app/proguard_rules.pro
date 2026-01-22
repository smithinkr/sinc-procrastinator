-keep class com.sinc.procrastinator.ProcrastinatorWidgetProvider { *; }
-keep class es.antonborri.home_widget.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes Signature
-keepattributes InnerClasses
-keep class com.google.firebase.** { *; }
# Only keep the data contract, keep everything else mangled
-keepclassmembers class com.sinc.procrastinator.models.Task {
    <fields>;
}