# The Daily reminder (flutter_local_notifications) stores its scheduled
# notifications as JSON through Gson. R8 in full mode — the default since
# AGP 8 — strips the generic type information Gson needs, and every cancel or
# reschedule then fails with "Missing type parameter" in release builds only.
# Rules from Gson's own Android example, plus the plugin's models.

# Gson reads generic types and annotations from the class files.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Keep the generic signatures of TypeToken and its subclasses (R8 3.0+).
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# The saved JSON uses the models' field names. Unrenamed, a notification
# saved by one release still reads back in the next.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
