package com.familypulse.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

class BlockedAppActivity : Activity() {

    companion object {
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
        const val EXTRA_BLOCKED_APP_NAME = "blocked_app_name"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val blockedPkg = intent.getStringExtra(EXTRA_BLOCKED_PACKAGE) ?: ""
        val appName = intent.getStringExtra(EXTRA_BLOCKED_APP_NAME)
            ?.takeIf { it.isNotBlank() }
            ?: resolveAppLabel(blockedPkg)

        buildUi(blockedPkg, appName)
    }

    private fun resolveAppLabel(pkg: String): String {
        if (pkg.isBlank()) return "Приложение"
        return try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            pkg
        }
    }

    private fun buildUi(blockedPkg: String, appName: String) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0F172A"))
            val pad = dp(24)
            setPadding(pad, pad, pad, pad)
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1E293B"))
                cornerRadius = dp(24).toFloat()
                setStroke(dp(1), Color.parseColor("#38BDF8"))
            }
            val p = dp(24)
            setPadding(p, dp(28), p, dp(24))
        }

        val badgeView = TextView(this).apply {
            text = "ДОСТУП ОГРАНИЧЕН"
            textSize = 12f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.parseColor("#38BDF8"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(12))
        }

        val titleView = TextView(this).apply {
            text = "Родитель запретил тебе пользоваться «$appName»"
            textSize = 20f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(10))
        }

        val subtitleView = TextView(this).apply {
            text = "Ты можешь вернуться назад или отправить запрос родителям в семейный чат."
            textSize = 14f
            setTextColor(Color.parseColor("#94A3B8"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(24))
        }

        val askButton = Button(this).apply {
            text = "СПРОСИТЬ РАЗРЕШЕНИЕ НА ИСПОЛЬЗОВАНИЕ"
            textSize = 13.5f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.parseColor("#0F172A"))
            isAllCaps = false
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#38BDF8"))
                cornerRadius = dp(16).toFloat()
            }
            setPadding(dp(16), dp(14), dp(16), dp(14))
            setOnClickListener {
                saveUnlockRequestAndNotify(blockedPkg, appName)
            }
        }

        val backButton = Button(this).apply {
            text = "НАЗАД"
            textSize = 14f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.WHITE)
            isAllCaps = false
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#334155"))
                cornerRadius = dp(16).toFloat()
            }
            setPadding(dp(16), dp(14), dp(16), dp(14))
            setOnClickListener {
                goHomeAndFinish()
            }
        }

        val btnParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = dp(12)
        }

        val backParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )

        card.addView(badgeView)
        card.addView(titleView)
        card.addView(subtitleView)
        card.addView(askButton, btnParams)
        card.addView(backButton, backParams)

        val cardParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        root.addView(card, cardParams)
        setContentView(root)
    }

    private fun saveUnlockRequestAndNotify(blockedPkg: String, appName: String) {
        val prefs = getSharedPreferences("family_pulse_native", Context.MODE_PRIVATE)
        val lastPkg = prefs.getString("last_unlock_req_pkg", "") ?: ""
        val lastTs = prefs.getLong("last_unlock_req_ts", 0L)
        val now = System.currentTimeMillis()

        // Антиспам: повторный запрос по тому же приложению не чаще 1 раза в 3 минуты
        if (lastPkg == blockedPkg && (now - lastTs) < 180_000L) {
            Toast.makeText(
                this,
                "Запрос по «$appName» уже отправлен родителям",
                Toast.LENGTH_SHORT
            ).show()
            goHomeAndFinish()
            return
        }

        prefs.edit()
            .putString("pending_unlock_pkg", blockedPkg)
            .putString("pending_unlock_name", appName)
            .putLong("pending_unlock_ts", now)
            .putString("last_unlock_req_pkg", blockedPkg)
            .putLong("last_unlock_req_ts", now)
            .apply()

        Toast.makeText(
            this,
            "Запрос отправлен родителям в чат",
            Toast.LENGTH_SHORT
        ).show()

        // Будим MainActivity для мгновенной отправки в Firebase и возвращаемся на домашний экран
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        if (launchIntent != null) {
            startActivity(launchIntent)
        }
        finish()
    }

    private fun goHomeAndFinish() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        goHomeAndFinish()
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}