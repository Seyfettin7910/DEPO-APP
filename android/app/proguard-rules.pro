# Yayın (release) derlemesinde kod küçültücü (R8), yalnızca yerel köprü (JNI)
# üzerinden çağrılan metotları "kullanılmıyor" sanıp silebiliyor. Bu da
# açılışta "NoSuchMethodError ... SharedPreferencesApiRegistrar.getAll"
# hatasına yol açıyor. Flutter eklentilerini olduğu gibi tut.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class dev.fluttercommunity.** { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-dontwarn io.flutter.embedding.**
