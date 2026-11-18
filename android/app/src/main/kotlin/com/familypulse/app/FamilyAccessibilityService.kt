package com.familypulse.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityEvent

class FamilyAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: FamilyAccessibilityService? = null
    }

    private val defaultRestricted = setOf(
        "com.android.settings",
        "com.android.vending",
        "com.google.android.packageinstaller",
        "com.android.packageinstaller",
        "com.google.android.permissioncontroller",
        "com.android.permissioncontroller",
        "com.miui.securitycenter",
        "com.coloros.safecenter",
        "com.huawei.systemmanager"
    )

    @Volatile
    private var currentForegroundPkg: String = ""

    @Volatile
    private var currentForegroundCls: String = ""

    private var lastBlockedPkg: String = ""
    private var lastBlockedTime: Long = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }

    private fun isFamilyShieldDefaultLauncher(): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
            }
            val resolveInfo = packageManager.resolveActivity(intent, 0)
            resolveInfo?.activityInfo?.packageName == packageName
        } catch (_: Exception) {
            false
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        val cls = event.className?.toString() ?: ""

        if (pkg == "com.android.systemui") return

        currentForegroundPkg = pkg
        currentForegroundCls = cls

        if (pkg == packageName) return
        evaluateAndEnforce(pkg, cls, forceImmediate = false)
    }

    /**
     * Вызывается мгновенно при обновлении списка blocked_packages из Firebase/Dart,
     * чтобы закрыть приложение, даже если ребёнок прямо сейчас в нём находится.
     */
    fun enforceProtectionNow() {
        val pkg = currentForegroundPkg
        val cls = currentForegroundCls
        if (pkg.isEmpty() || pkg == packageName || pkg == "com.android.systemui") return
        evaluateAndEnforce(pkg, cls, forceImmediate = true)
    }

    private fun evaluateAndEnforce(pkg: String, cls: String, forceImmediate: Boolean) {
        val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)

        val isSetupCompleted = prefs.getBoolean("setup_completed", false)
        if (!isSetupCompleted) return

        val bypassUntil = prefs.getLong("parent_bypass_until", 0L)
        if (System.currentTimeMillis() < bypassUntil) return

        val dynamicBlocked = prefs.getStringSet("blocked_packages", emptySet()) ?: emptySet()

        val isGmsRestrictedWindow = pkg == "com.google.android.gms" && (
            cls.contains("Location", ignoreCase = true) ||
            cls.contains("Permission", ignoreCase = true) ||
            cls.contains("Privacy", ignoreCase = true) ||
            cls.contains("AppOps", ignoreCase = true) ||
            cls.contains("DeviceAdmin", ignoreCase = true) ||
            cls.contains("ManageSpace", ignoreCase = true)
        )

        val isSystemRestricted = defaultRestricted.contains(pkg) ||
            isGmsRestrictedWindow ||
            (pkg == "com.android.settings" && cls.contains("DeviceAdminAdd", ignoreCase = true))

        val isAppBlockedByParent = dynamicBlocked.contains(pkg)

        if (!isSystemRestricted && !isAppBlockedByParent) return

        val now = System.currentTimeMillis()
        if (!forceImmediate && pkg == lastBlockedPkg && (now - lastBlockedTime) < 600L) return
        lastBlockedPkg = pkg
        lastBlockedTime = now

        val isLauncherMode = isFamilyShieldDefaultLauncher()

        if (!isLauncherMode) {
            if (isAppBlockedByParent && !isSystemRestricted) {
                val appLabel = try {
                    val info = packageManager.getApplicationInfo(pkg, 0)
                    packageManager.getApplicationLabel(info).toString()
                } catch (_: PackageManager.NameNotFoundException) {
                    pkg
                }

                val blockIntent = Intent(this, BlockedAppActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                    )
                    putExtra(BlockedAppActivity.EXTRA_BLOCKED_PACKAGE, pkg)
                    putExtra(BlockedAppActivity.EXTRA_BLOCKED_APP_NAME, appLabel)
                }
                startActivity(blockIntent)
            } else {
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        } else {
            performGlobalAction(GLOBAL_ACTION_HOME)
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            if (launchIntent != null) {
                startActivity(launchIntent)
            }
        }
    }

    override fun onInterrupt() {}
}