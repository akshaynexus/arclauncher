## Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication

## media_kit (mpv/libmpv native bindings)
-keep class com.alexmercerind.** { *; }
-keep class is.xyz.** { *; }
-dontwarn com.alexmercerind.**
-dontwarn is.xyz.**

## media_kit native JNI
-keepclasseswithmembernames class * {
    native <methods>;
}

## Keep MediaKit initialization
-keep class media_kit.** { *; }
-dontwarn media_kit.**

## Provider / ChangeNotifier — R8 strips notifyListeners & breaks rebuilds
-keep class * extends ChangeNotifier { *; }
-keep class * implements ChangeNotifier { *; }
-keepclassmembers class * {
    void notifyListeners();
}
-keep class * extends State { *; }
-keep class * extends StatefulWidget { *; }
-keep class * extends StatelessWidget { *; }
-keep class * extends NavigatorObserver { *; }
-keep class * implements LocalKey { *; }
-keep class * extends InheritedWidget { *; }
-keep class provider.** { *; }
-keep class com.github.provider.** { *; }

## Drift database
-keep class drift.** { *; }
-keep class * extends drift.** { *; }
-keep class * extends drift.Database { *; }
-keep class **.*_Dao { *; }
-keep class **.*_TableInfo { *; }
-dontwarn drift.**

## SharedPreferences
-keep class * implements SharedPreferences { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

## EasyLocalization
-keep class com.ekunicode.easy_localization.** { *; }
-keep class * extends easy_localization.** { *; }

## screen_brightness / wakelock_plus / package_info_plus
-keep class com.**.screen_brightness.** { *; }
-keep class com.**.wakelock_plus.** { *; }
-keep class com.**.package_info_plus.** { *; }

## App's native platform channel handlers — R8 strips configureFlutterEngine
## and MethodChannel handlers if not explicitly kept
-keep class me.efesser.flauncher.** { *; }
-keep class com.leanbitlab.ltvL.** { *; }