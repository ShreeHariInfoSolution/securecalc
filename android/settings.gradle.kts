@Suppress("UNCHECKED_CAST")
try {
    System.clearProperty("ANDROID_PREFS_ROOT")
    System.clearProperty("ANDROID_SDK_HOME")

    val processEnv = Class.forName("java.lang.ProcessEnvironment")
    fun clearVar(fieldName: String) {
        try {
            val field = processEnv.getDeclaredField(fieldName).apply { isAccessible = true }
            val map = field.get(null) as? MutableMap<*, *>
            map?.keys?.removeAll { key ->
                val k = key.toString()
                k.equals("ANDROID_PREFS_ROOT", ignoreCase = true) || k.equals("ANDROID_SDK_HOME", ignoreCase = true)
            }
        } catch (_: Throwable) {}
    }

    clearVar("theEnvironment")
    clearVar("theUnmodifiableEnvironment")
    clearVar("theCaseInsensitiveEnvironment")
} catch (_: Throwable) {}

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
