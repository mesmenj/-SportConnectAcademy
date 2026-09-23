# Flutter engine classes are loaded through JNI and must retain their names.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep native method declarations while allowing R8 to optimize everything else.
-keepclasseswithmembernames class * {
    native <methods>;
}
