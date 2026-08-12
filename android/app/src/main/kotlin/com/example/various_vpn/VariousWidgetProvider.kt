package com.example.various_vpn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Домашний виджет Various VPN. Значения приходят из Flutter (home_widget):
 *  vv_connected, vv_status, vv_flag_img (путь к отрисованному флагу),
 *  vv_server, vv_ping, vv_button.
 *
 * Тап по КАРТОЧКЕ (не по кнопке) — открывает приложение.
 * Тап по кнопке вкл/выкл и по кнопке пинга — НЕ открывает приложение,
 * а шлёт broadcast в [VariousWidgetActionReceiver], который делает всё нативно.
 */
class VariousWidgetProvider : HomeWidgetProvider() {

    /**
     * Значок для шапки виджета по выбранному варианту иконки приложения.
     * Имя ресурса ищем по строке: так добавление нового варианта не требует
     * править этот код. Не нашли — показываем классический.
     */
    private fun badgeFor(context: Context, key: String?): Int {
        val name = "vv_badge_" + (key ?: "classic")
        val id = context.resources.getIdentifier(
            name, "drawable", context.packageName)
        return if (id != 0) id else R.drawable.vv_badge_classic
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.vv_widget).apply {
                val connected = widgetData.getString("vv_connected", "false") == "true"
                val status = widgetData.getString("vv_status", null)
                    ?: if (connected) "Protected" else "Disconnected"
                val server = widgetData.getString("vv_server", null) ?: "Not selected"
                val ping = widgetData.getString("vv_ping", null) ?: ""
                val button = widgetData.getString("vv_button", null)
                    ?: if (connected) "Disconnect" else "Connect"
                // Бесплатный режим: сервер подбирается сам и работает только
                // Telegram — мерить пинг нечего, поэтому кнопку замера прячем.
                val free = widgetData.getString("vv_free", "false") == "true"
                val hasServer = widgetData.getString("vv_has_server", "false") == "true"

                // Значок виджета следует за выбранной иконкой приложения.
                setImageViewResource(R.id.vv_badge, badgeFor(
                    context, widgetData.getString("vv_icon", null)))

                setTextViewText(R.id.vv_status, status)
                setTextViewText(R.id.vv_server, server)
                setTextViewText(R.id.vv_ping, ping)
                setTextViewText(R.id.vv_button, button)

                // Яркий флаг, отрисованный приложением (иначе — заглушка-глобус).
                val flagPath = widgetData.getString("vv_flag_img", null)
                if (flagPath != null) {
                    val bmp = BitmapFactory.decodeFile(flagPath)
                    if (bmp != null) setImageViewBitmap(R.id.vv_flag, bmp)
                }

                if (connected) {
                    setTextColor(R.id.vv_status, 0xFF9BCB3C.toInt())
                    setImageViewResource(R.id.vv_dot, R.drawable.vv_dot_on)
                    setInt(R.id.vv_button, "setBackgroundResource", R.drawable.vv_btn_disconnect)
                    setTextColor(R.id.vv_button, 0xFFE2504A.toInt())
                } else {
                    setTextColor(R.id.vv_status, 0xFFFFFFFF.toInt())
                    setImageViewResource(R.id.vv_dot, R.drawable.vv_dot_off)
                    setInt(R.id.vv_button, "setBackgroundResource", R.drawable.vv_btn_connect)
                    setTextColor(R.id.vv_button, 0xFF0C1206.toInt())
                }
                setViewVisibility(R.id.vv_ping,
                    if (ping.isEmpty()) View.GONE else View.VISIBLE)
                setViewVisibility(R.id.vv_ping_btn, if (free) View.GONE else View.VISIBLE)
                // В free-режиме вместо флага страны — значок Telegram.
                setViewVisibility(R.id.vv_tg, if (free) View.VISIBLE else View.GONE)
                // Флаг показываем только когда сервер реально выбран и это не
                // бесплатный режим (там вместо него значок Telegram).
                setViewVisibility(R.id.vv_flag,
                    if (free || !hasServer) View.GONE else View.VISIBLE)

                // Тап по карточке — открыть приложение.
                val open = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("vvpn://open")
                )
                setOnClickPendingIntent(R.id.vv_root, open)

                // Кнопка вкл/выкл — нативный toggle, БЕЗ открытия приложения.
                setOnClickPendingIntent(
                    R.id.vv_button,
                    actionIntent(context, VariousWidgetActionReceiver.ACTION_TOGGLE, widgetId)
                )
                // Кнопка измерения пинга — нативный замер, без открытия.
                setOnClickPendingIntent(
                    R.id.vv_ping_btn,
                    actionIntent(context, VariousWidgetActionReceiver.ACTION_PING, widgetId)
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun actionIntent(context: Context, action: String, widgetId: Int): PendingIntent {
        val intent = Intent(context, VariousWidgetActionReceiver::class.java).apply {
            this.action = action
            data = Uri.parse("vvpn://action/$action/$widgetId")
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, action.hashCode(), intent, flags)
    }
}
