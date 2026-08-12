package com.example.various_vpn

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import dev.amirzr.flutter_v2ray_client.v2ray.V2rayController
import dev.amirzr.flutter_v2ray_client.v2ray.utils.AppConfigs
import java.util.concurrent.Executors
import javax.net.ssl.SSLSocketFactory

/**
 * Обрабатывает нажатия на кнопки виджета БЕЗ открытия приложения:
 *  - ACTION_TOGGLE — включить/выключить VPN нативно (V2rayController).
 *  - ACTION_PING   — измерить пинг активного сервера (tcp/tls, как в приложении).
 *
 * Данные (конфиг для старта, хост/порт/тип пинга, локализованные подписи)
 * приложение заранее сохраняет в HomeWidgetPreferences.
 */
class VariousWidgetActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_TOGGLE = "com.example.various_vpn.WIDGET_TOGGLE"
        const val ACTION_PING = "com.example.various_vpn.WIDGET_PING"
        private const val PREFS = "HomeWidgetPreferences"
        private val pool = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TOGGLE -> handleToggle(context.applicationContext)
            ACTION_PING -> handlePing(context.applicationContext)
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun handleToggle(context: Context) {
        val p = prefs(context)
        val connected = V2rayController.getConnectionState() ==
            AppConfigs.V2RAY_STATES.V2RAY_CONNECTED
        if (connected) {
            V2rayController.StopV2ray(context)
            optimistic(context, false)
        } else {
            val config = p.getString("vv_config", null)
            val remark = p.getString("vv_remark", "Various VPN") ?: "Various VPN"
            if (config.isNullOrEmpty()) {
                // Нет сохранённого конфига — включить нельзя, откроем приложение.
                openApp(context)
                return
            }
            val blocked = ArrayList(
                (p.getString("vv_blocked", "") ?: "")
                    .split("\n").filter { it.isNotBlank() }
            )
            V2rayController.changeConnectionMode(
                AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN
            )
            V2rayController.StartV2ray(context, remark, config, blocked, ArrayList())
            optimistic(context, true)
        }
        refresh(context)
    }

    private fun handlePing(context: Context) {
        val p = prefs(context)
        val host = p.getString("vv_ping_host", null)
        val port = p.getInt("vv_ping_port", 0)
        if (host.isNullOrEmpty() || port == 0) return
        val tls = (p.getString("vv_ping_type", "tcp") ?: "tcp") == "proxy"
        // индикатор «измеряю…»
        p.edit().putString("vv_ping", "…").apply()
        refresh(context)
        pool.execute {
            val ms = measure(host, port, tls)
            p.edit().putString("vv_ping", if (ms < 0) "—" else "$ms ms").apply()
            refresh(context)
        }
    }

    /** TCP- или TLS-хендшейк пинг (как tcpPing/tlsPing в приложении). */
    private fun measure(host: String, port: Int, tls: Boolean): Long {
        return try {
            val start = System.nanoTime()
            if (tls) {
                val f = SSLSocketFactory.getDefault() as SSLSocketFactory
                f.createSocket().use { raw ->
                    val s = raw as javax.net.ssl.SSLSocket
                    s.connect(java.net.InetSocketAddress(host, port), 2500)
                    s.startHandshake()
                }
            } else {
                java.net.Socket().use { s ->
                    s.connect(java.net.InetSocketAddress(host, port), 2500)
                }
            }
            (System.nanoTime() - start) / 1_000_000
        } catch (e: Exception) {
            -1
        }
    }

    private fun optimistic(context: Context, connected: Boolean) {
        val p = prefs(context)
        val status = if (connected)
            p.getString("vv_lbl_protected", "Protected")
        else p.getString("vv_lbl_disconnected", "Disconnected")
        val button = if (connected)
            p.getString("vv_lbl_disconnect", "Disconnect")
        else p.getString("vv_lbl_connect", "Connect")
        p.edit()
            .putString("vv_connected", if (connected) "true" else "false")
            .putString("vv_status", status)
            .putString("vv_button", button)
            .apply()
    }

    private fun refresh(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(
            ComponentName(context, VariousWidgetProvider::class.java)
        )
        val intent = Intent(context, VariousWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(intent)
    }

    private fun openApp(context: Context) {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (launch != null) context.startActivity(launch)
    }
}
