## Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

## TensorFlow Lite
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-keep interface org.tensorflow.lite.gpu.** { *; }

## Google ML Kit
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }

## Camera
-keep class androidx.camera.** { *; }
-keep interface androidx.camera.** { *; }

## Prevent obfuscation of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

## Keep custom model classes if any
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
