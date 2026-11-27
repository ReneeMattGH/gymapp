# Kotlin serialization keeps generated serializers through their companion objects.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.gymapp.android.**$$serializer { *; }
-keepclassmembers class com.gymapp.android.** {
    *** Companion;
}
-keepclasseswithmembers class com.gymapp.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Retrofit + OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**
-keepattributes Signature, Exceptions
