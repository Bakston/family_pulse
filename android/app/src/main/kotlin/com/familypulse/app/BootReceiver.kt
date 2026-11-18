package com.familypulse.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {

            // Гарантированно обнуляем 5-минутный обход при перезагрузке
            context.getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
                .edit()
                .putLong("parent_bypass_until", 0L)
                .apply()

            // Запускаем приложение только если устройство настроено как телефон ребёнка
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val userType = flutterPrefs.getString("flutter.user_type", "") ?: ""
            if (userType != "child") return

            val homeIntent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
            val isLauncher = context.packageManager.resolveActivity(homeIntent, 0)
                ?.activityInfo?.packageName == context.packageName

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                if (!isLauncher) {
                    putExtra("background_boot", true)
                }
            }
            if (launchIntent != null) {
                context.startActivity(launchIntent)
            }
        }
    }
}