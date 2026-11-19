package com.familypulse.app

import android.app.Activity
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import android.text.TextUtils
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Calendar

class MainActivity : FlutterFragmentActivity() {
    private val USAGE_CHANNEL = "com.example.family_pulse/usage_stats"
    private val ADMIN_CHANNEL = "com.example.family_pulse/device_admin"
    private val VPN_REQUEST_CODE = 7071

    private var pendingVpnResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleBackgroundBootIfNeeded(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleBackgroundBootIfNeeded(intent)
    }

    private fun handleBackgroundBootIfNeeded(intent: Intent?) {
        if (intent?.getBooleanExtra("background_boot", false) == true) {
            intent.removeExtra("background_boot")
            if (!isDefaultLauncher()) {
                window?.decorView?.postDelayed({
                    try {
                        moveTaskToBack(true)
                    } catch (_: Exception) {}
                }, 1200L)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // При холодном запуске сбрасываем временные обходы
        getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
            .edit()
            .putLong("parent_bypass_until", 0L)
            .putLong("update_bypass_until", 0L)
            .apply()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getUsageStats" -> {
                    try {
                        result.success(getAppUsageStats())
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", e.message, null)
                    }
                }

                "checkUsagePermission" -> result.success(checkUsageStatsPermission())
                "requestUsagePermission" -> {
                    try {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        } catch (e2: Exception) {
                            openAppDetailsFallback()
                        }
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ADMIN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setChildMode" -> {
                    val mode = call.argument<String>("mode") ?: "launcher"
                    val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                    prefs.edit().putString("child_mode", mode).apply()
                    result.success(true)
                }

                "getChildMode" -> {
                    val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                    result.success(prefs.getString("child_mode", "launcher") ?: "launcher")
                }

                "consumePendingUnlockRequest" -> {
                    val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                    val pkg = prefs.getString("pending_unlock_pkg", null)
                    val name = prefs.getString("pending_unlock_name", null)
                    val ts = prefs.getLong("pending_unlock_ts", 0L)
                    if (!pkg.isNullOrEmpty()) {
                        prefs.edit()
                            .remove("pending_unlock_pkg")
                            .remove("pending_unlock_name")
                            .remove("pending_unlock_ts")
                            .apply()
                        result.success(mapOf(
                            "packageName" to pkg,
                            "appName" to (name ?: pkg),
                            "timestamp" to ts
                        ))
                    } else {
                        result.success(null)
                    }
                }

                "checkDeviceAdmin" -> result.success(isDeviceAdminActive())
                "requestDeviceAdmin" -> {
                    try {
                        val compName = ComponentName(this, DeviceAdminReceiver::class.java)
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, compName)
                            putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Защита FamilyPulse от удаления ребёнком")
                        }
                        startActivity(intent)
                    } catch (e: Exception) {
                        openAppDetailsFallback()
                    }
                    result.success(true)
                }

                "checkAccessibility" -> result.success(isAccessibilityServiceEnabled())
                "requestAccessibility" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    } catch (e: Exception) {
                        openAppDetailsFallback()
                    }
                    result.success(true)
                }

                "checkOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }

                "requestOverlayPermission" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
                        } catch (e2: Exception) {
                            openAppDetailsFallback()
                        }
                    }
                    result.success(true)
                }

                "openPhoneDialer" -> {
                    try {
                        val intent = Intent(Intent.ACTION_DIAL).apply {
                            data = Uri.parse("tel:")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "checkDefaultLauncher" -> result.success(isDefaultLauncher())
                "requestDefaultLauncher" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_HOME)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        } catch (e2: Exception) {
                            openAppDetailsFallback()
                        }
                    }
                    result.success(true)
                }

                "setBlockedPackages" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                    prefs.edit().putStringSet("blocked_packages", packages.toSet()).apply()
                    FamilyAccessibilityService.instance?.enforceProtectionNow()
                    result.success(true)
                }

                "setParentBypass" -> {
                    val minutes = call.argument<Int>("minutes") ?: 0
                    val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                    val bypassUntil = if (minutes > 0) {
                        System.currentTimeMillis() + minutes * 60_000L
                    } else {
                        0L
                    }
                    prefs.edit().putLong("parent_bypass_until", bypassUntil).apply()
                    result.success(true)
                }

                "getUpdateDirectoryPath" -> {
                    val dir = applicationContext.getExternalFilesDir("updates")
                    if (dir != null && !dir.exists()) {
                        dir.mkdirs()
                    }
                    result.success(dir?.absolutePath)
                }

                "installOwnUpdateApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val apkFile = File(filePath)
                        if (!apkFile.exists()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        // Даём карт-бланш на установку нашего обновления на 3 минуты на обеих ролях
                        val until = System.currentTimeMillis() + 3 * 60_000L
                        getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                            .edit()
                            .putLong("update_bypass_until", until)
                            .putLong("parent_bypass_until", until)
                            .apply()

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                            val permIntent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(permIntent)
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val apkUri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apkFile
                        )

                        @Suppress("DEPRECATION")
                        val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                        }

                        // Направляем напрямую в системный PackageInstaller, минуя Huawei AppGallery
                        val systemInstaller = listOf(
                            "com.google.android.packageinstaller",
                            "com.android.packageinstaller"
                        ).firstOrNull { pkg ->
                            try {
                                packageManager.getPackageInfo(pkg, 0)
                                true
                            } catch (_: Exception) {
                                false
                            }
                        }
                        if (systemInstaller != null) {
                            installIntent.setPackage(systemInstaller)
                        }

                        startActivity(installIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }

                "setSetupCompleted" -> {
                    val completed = call.argument<Boolean>("completed") ?: true
                    val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("setup_completed", completed).apply()
                    result.success(true)
                }

                // --- МЕТОДЫ ВЕБ-ФИЛЬТРАЦИИ (VPN) ---
                "checkVpnPermission" -> {
                    val prepareIntent = VpnService.prepare(this)
                    result.success(prepareIntent == null)
                }

                "requestVpnPermission" -> {
                    val prepareIntent = VpnService.prepare(this)
                    if (prepareIntent == null) {
                        result.success(true)
                    } else {
                        pendingVpnResult = result
                        startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                    }
                }

                "isVpnActive" -> {
                    result.success(FamilyVpnService.isRunning)
                }

                "updateWebFilterRules" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val mode = call.argument<String>("mode") ?: "blacklist"
                    val blockAdult = call.argument<Boolean>("blockAdult") ?: true
                    val blocked = call.argument<List<String>>("blockedDomains") ?: emptyList()
                    val allowed = call.argument<List<String>>("allowedDomains") ?: emptyList()

                    val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putBoolean("web_filter_enabled", enabled)
                        .putString("web_filter_mode", mode)
                        .putBoolean("web_filter_block_adult", blockAdult)
                        .putStringSet("web_filter_blocked", blocked.toSet())
                        .putStringSet("web_filter_allowed", allowed.toSet())
                        .apply()

                    if (enabled && VpnService.prepare(this) == null) {
                        startVpnServiceWithAction(FamilyVpnService.ACTION_RELOAD_RULES)
                    } else if (!enabled) {
                        startVpnServiceWithAction(FamilyVpnService.ACTION_STOP)
                    }
                    result.success(true)
                }

                "stopWebFilter" -> {
                    startVpnServiceWithAction(FamilyVpnService.ACTION_STOP)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            val granted = resultCode == Activity.RESULT_OK
            pendingVpnResult?.success(granted)
            pendingVpnResult = null
        }
    }

    private fun startVpnServiceWithAction(action: String) {
        try {
            val intent = Intent(this, FamilyVpnService::class.java).apply {
                this.action = action
            }
            if (action != FamilyVpnService.ACTION_STOP && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {}
    }

    private fun openAppDetailsFallback() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (_: Exception) {}
    }

    private fun isDefaultLauncher(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
        }
        val resolveInfo = packageManager.resolveActivity(intent, 0)
        return resolveInfo?.activityInfo?.packageName == packageName
    }

    private fun isDeviceAdminActive(): Boolean {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val compName = ComponentName(this, DeviceAdminReceiver::class.java)
        return dpm.isAdminActive(compName)
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedComponent = ComponentName(this, FamilyAccessibilityService::class.java)
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServices)
        while (colonSplitter.hasNext()) {
            val componentNameString = colonSplitter.next()
            val enabledService = ComponentName.unflattenFromString(componentNameString)
            if (enabledService != null && enabledService == expectedComponent) {
                return true
            }
        }
        return false
    }

    private fun getAppUsageStats(): Map<String, Long> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, calendar.timeInMillis, System.currentTimeMillis()
        )
        val usageMap = mutableMapOf<String, Long>()
        if (stats != null) {
            for (stat in stats) {
                if (stat.totalTimeInForeground > 0) {
                    usageMap[stat.packageName] = (usageMap[stat.packageName] ?: 0L) + stat.totalTimeInForeground
                }
            }
        }
        return usageMap
    }

    private fun checkUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }
}