package com.shis.securecalc

import android.content.Context
import android.media.MediaDrm
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

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
                        val prefs = getSharedPreferences("securecalc_device_identity", Context.MODE_PRIVATE)
                        val storedId = prefs.getString("persistent_device_id", null)
                        if (!storedId.isNullOrEmpty()) {
                            result.success(storedId)
                            return@setMethodCallHandler
                        }

                        val hardwareUniqueId = getHardwareUniqueId()
                        val manufacturer = Build.MANUFACTURER.lowercase().replace(" ", "")
                        val model = Build.MODEL.lowercase().replace(" ", "")
                        val hardwareId = if (hardwareUniqueId.isNotEmpty()) {
                            "${manufacturer}${model}_${hardwareUniqueId}"
                        } else {
                            "${manufacturer}${model}"
                        }

                        if (hardwareId.isNotEmpty()) {
                            prefs.edit().putString("persistent_device_id", hardwareId).apply()
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

    private fun getHardwareUniqueId(): String {
        // 1. Try MediaDrm Widevine Hardware ID (survives app uninstalls & reinstalls)
        try {
            val widevineUuid = UUID(-0x121074568629b532L, -0x5c37d823277d3f02L)
            val mediaDrm = MediaDrm(widevineUuid)
            val widevineId = mediaDrm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                mediaDrm.close()
            } else {
                @Suppress("DEPRECATION")
                mediaDrm.release()
            }
            if (widevineId != null && widevineId.isNotEmpty()) {
                val sb = StringBuilder()
                for (b in widevineId) {
                    sb.append(String.format("%02x", b))
                }
                val drmId = sb.toString()
                if (drmId.isNotEmpty()) {
                    return if (drmId.length > 16) drmId.substring(drmId.length - 16) else drmId
                }
            }
        } catch (_: Exception) {
        }

        // 2. Fallback to Settings.Secure.ANDROID_ID
        return Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
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
