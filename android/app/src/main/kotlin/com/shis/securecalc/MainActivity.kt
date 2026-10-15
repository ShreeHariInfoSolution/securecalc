package com.shis.securecalc

import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.shis.securecalc/security"
    private var isSecureEnabled = true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureFlag" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    isSecureEnabled = enable
                    applySecureFlag(enable)
                    result.success(true)
                }
                "getSystemDeviceId" -> {
                    try {
                        val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
                        val manufacturer = Build.MANUFACTURER.lowercase()
                        val model = Build.MODEL.lowercase()
                        val hardwareId = if (androidId.isNotEmpty()) {
                            "${manufacturer}${model}_${androidId}"
                        } else {
                            "${manufacturer}${model}"
                        }
                        result.success(hardwareId)
                    } catch (e: Exception) {
                        result.error("DEVICE_ID_ERROR", e.toString(), null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        applySecureFlag(isSecureEnabled)
    }

    private fun applySecureFlag(enable: Boolean) {
        try {
            if (enable) {
                window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        } catch (_: Exception) {
        }
    }
}
